import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_template_rules.dart';
import 'package:sitemark/workflow/capture_template_service.dart';

void main() {
  group('CaptureTemplateService', () {
    late AppDatabase database;
    late CaptureTemplateService service;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      service = CaptureTemplateService(database: database);
      await database.createProject(id: 'project-1', name: '东区厂房改造');
      await database.createProject(id: 'project-2', name: '西区厂房改造');
    });

    tearDown(() => database.close());

    test(
      'creates normalized templates and rejects project-scoped duplicates',
      () async {
        final created = await service.create(
          projectId: 'project-1',
          name: '  日常   巡检  ',
          workLocation: '  A 区 ',
          workContent: ' 风管检查 ',
          photographer: ' 张工 ',
        );

        expect(created.name, '日常 巡检');
        expect(created.nameKey, '日常 巡检');
        expect(created.workLocation, 'A 区');
        expect(created.workContent, '风管检查');
        expect(created.photographer, '张工');
        await expectFailure(
          () => service.create(
            projectId: 'project-1',
            name: '日常 巡检',
            workLocation: 'B 区',
            workContent: '复查',
            photographer: '李工',
          ),
          CaptureTemplateFailure.duplicateName,
        );
        expect(
          (await service.create(
            projectId: 'project-2',
            name: '日常 巡检',
            workLocation: 'B 区',
            workContent: '复查',
            photographer: '李工',
          )).projectId,
          'project-2',
        );
      },
    );

    test('validates all editable template fields', () async {
      final tooLongName = 'x' * (captureTemplateNameMaxLength + 1);
      final tooLongLocation = 'x' * (captureTemplateLocationMaxLength + 1);
      final tooLongContent = 'x' * (captureTemplateContentMaxLength + 1);
      final tooLongPhotographer =
          'x' * (captureTemplatePhotographerMaxLength + 1);

      await expectFailure(
        () => service.create(
          projectId: 'project-1',
          name: ' ',
          workLocation: 'A 区',
          workContent: '检查',
          photographer: '张工',
        ),
        CaptureTemplateFailure.emptyName,
      );
      await expectFailure(
        () => service.create(
          projectId: 'project-1',
          name: tooLongName,
          workLocation: 'A 区',
          workContent: '检查',
          photographer: '张工',
        ),
        CaptureTemplateFailure.nameTooLong,
      );
      await expectFailure(
        () => service.create(
          projectId: 'project-1',
          name: '模板',
          workLocation: ' ',
          workContent: '检查',
          photographer: '张工',
        ),
        CaptureTemplateFailure.emptyWorkLocation,
      );
      await expectFailure(
        () => service.create(
          projectId: 'project-1',
          name: '模板',
          workLocation: tooLongLocation,
          workContent: '检查',
          photographer: '张工',
        ),
        CaptureTemplateFailure.workLocationTooLong,
      );
      await expectFailure(
        () => service.create(
          projectId: 'project-1',
          name: '模板',
          workLocation: 'A 区',
          workContent: ' ',
          photographer: '张工',
        ),
        CaptureTemplateFailure.emptyWorkContent,
      );
      await expectFailure(
        () => service.create(
          projectId: 'project-1',
          name: '模板',
          workLocation: 'A 区',
          workContent: tooLongContent,
          photographer: '张工',
        ),
        CaptureTemplateFailure.workContentTooLong,
      );
      await expectFailure(
        () => service.create(
          projectId: 'project-1',
          name: '模板',
          workLocation: 'A 区',
          workContent: '检查',
          photographer: ' ',
        ),
        CaptureTemplateFailure.emptyPhotographer,
      );
      await expectFailure(
        () => service.create(
          projectId: 'project-1',
          name: '模板',
          workLocation: 'A 区',
          workContent: '检查',
          photographer: tooLongPhotographer,
        ),
        CaptureTemplateFailure.photographerTooLong,
      );
    });

    test('maps an insert uniqueness race to duplicateName', () async {
      final raceDatabase = _CountStaleDatabase(NativeDatabase.memory());
      addTearDown(raceDatabase.close);
      await raceDatabase.createProject(id: 'project-1', name: '东区厂房改造');
      await raceDatabase.insertCaptureTemplate(
        CaptureTemplatesCompanion.insert(
          id: 'existing',
          projectId: 'project-1',
          name: 'Existing',
          nameKey: 'existing',
          workLocation: 'A 区',
          workContent: '检查',
          photographer: '张工',
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        ),
      );
      final racingService = CaptureTemplateService(database: raceDatabase);
      await expectFailure(
        () => racingService.create(
          projectId: 'project-1',
          name: '  EXISTING ',
          workLocation: 'B 区',
          workContent: '复查',
          photographer: '李工',
        ),
        CaptureTemplateFailure.duplicateName,
      );
    });

    test(
      'enforces the per-project limit inside the create transaction',
      () async {
        for (var index = 0; index < captureTemplateLimitPerProject; index++) {
          await database.insertCaptureTemplate(
            CaptureTemplatesCompanion.insert(
              id: 'template-$index',
              projectId: 'project-1',
              name: '模板$index',
              nameKey: '模板$index',
              workLocation: 'A 区',
              workContent: '检查',
              photographer: '张工',
              createdAt: DateTime(2026, 8, 1),
              updatedAt: DateTime(2026, 8, 1),
            ),
          );
        }

        await expectFailure(
          () => service.create(
            projectId: 'project-1',
            name: '第 101 个',
            workLocation: 'A 区',
            workContent: '检查',
            photographer: '张工',
          ),
          CaptureTemplateFailure.projectLimitReached,
        );
      },
    );

    test(
      'rename and delete map absent project-scoped templates to notFound',
      () async {
        final template = await service.create(
          projectId: 'project-1',
          name: '日常巡检',
          workLocation: 'A 区',
          workContent: '检查',
          photographer: '张工',
        );

        final renamed = await service.rename(
          projectId: 'project-1',
          templateId: template.id,
          name: '  专项检查 ',
        );
        expect(renamed.name, '专项检查');
        await expectFailure(
          () => service.rename(
            projectId: 'project-2',
            templateId: template.id,
            name: '越权修改',
          ),
          CaptureTemplateFailure.notFound,
        );
        await expectFailure(
          () => service.delete(projectId: 'project-2', templateId: template.id),
          CaptureTemplateFailure.notFound,
        );
        await service.delete(projectId: 'project-1', templateId: template.id);
        await expectFailure(
          () => service.delete(projectId: 'project-1', templateId: template.id),
          CaptureTemplateFailure.notFound,
        );
      },
    );
  });
}

Future<void> expectFailure(
  Future<void> Function() action,
  CaptureTemplateFailure expected,
) {
  return expectLater(
    action(),
    throwsA(
      isA<CaptureTemplateException>().having(
        (error) => error.failure,
        'failure',
        expected,
      ),
    ),
  );
}

class _CountStaleDatabase extends AppDatabase {
  _CountStaleDatabase(super.executor) : super.forTesting();

  @override
  Future<int> countCaptureTemplates(String projectId) async => 0;

  @override
  Future<List<CaptureTemplate>> captureTemplatesForProject(
    String projectId,
  ) async => const [];
}

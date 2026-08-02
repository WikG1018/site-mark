import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_template_rules.dart';
import 'package:sitemark/workflow/capture_template_service.dart';

import '../support/capture_template_contract_fixtures.dart';

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

    test('uses the fixed cross-layer name and uniqueness fixtures', () async {
      for (final fixture in captureTemplateNameContractCases) {
        if (fixture.input == 'abc' || fixture.input == '模板a') {
          await expectFailure(
            () => service.create(
              projectId: 'project-1',
              name: fixture.input,
              workLocation: 'A 区',
              workContent: '检查',
              photographer: '张工',
            ),
            CaptureTemplateFailure.duplicateName,
          );
          continue;
        }
        final created = await service.create(
          projectId: 'project-1',
          name: fixture.input,
          workLocation: 'A 区',
          workContent: '检查',
          photographer: '张工',
        );
        expect(created.name, fixture.normalized, reason: fixture.label);
        expect(created.nameKey, fixture.key, reason: fixture.label);
      }

      expect(
        (await service.create(
          projectId: 'project-1',
          name: captureTemplate80Scalars,
          workLocation: 'A 区',
          workContent: '检查',
          photographer: '张工',
        )).name,
        captureTemplate80Scalars,
      );
      await expectFailure(
        () => service.create(
          projectId: 'project-2',
          name: captureTemplate81Scalars,
          workLocation: 'A 区',
          workContent: '检查',
          photographer: '张工',
        ),
        CaptureTemplateFailure.nameTooLong,
      );
    });

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

    test('rejects NUL with a dedicated failure in create and rename', () async {
      for (final fixture in captureTemplateNulFieldCases) {
        await expectFailure(
          () => service.create(
            projectId: 'project-1',
            name: fixture.name,
            workLocation: fixture.workLocation,
            workContent: fixture.workContent,
            photographer: fixture.photographer,
          ),
          CaptureTemplateFailure.invalidCharacter,
        );
      }
      final template = await service.create(
        projectId: 'project-1',
        name: '可重命名模板',
        workLocation: 'A 区',
        workContent: '检查',
        photographer: '张工',
      );
      await expectFailure(
        () => service.rename(
          projectId: 'project-1',
          templateId: template.id,
          name: 'rename\u0000template',
        ),
        CaptureTemplateFailure.invalidCharacter,
      );
    });

    test('maps an insert uniqueness race to duplicateName', () async {
      final raceDatabase = _InterleavingInsertDatabase(NativeDatabase.memory());
      addTearDown(raceDatabase.close);
      await raceDatabase.createProject(id: 'project-1', name: '东区厂房改造');
      raceDatabase.insertBeforeNextTemplate = CaptureTemplatesCompanion.insert(
        id: 'interleaving-template',
        projectId: 'project-1',
        name: 'Existing',
        nameKey: 'existing',
        workLocation: 'A 区',
        workContent: '检查',
        photographer: '张工',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
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
      expect(raceDatabase.countWasRead, isTrue);
      expect(raceDatabase.templatesWereRead, isTrue);
      expect(raceDatabase.events, ['count', 'templates', 'conflict']);
    });

    test('does not map a primary-key collision to duplicateName', () async {
      await database.insertCaptureTemplate(
        CaptureTemplatesCompanion.insert(
          id: 'colliding-id',
          projectId: 'project-1',
          name: 'Existing template',
          nameKey: 'existing template',
          workLocation: 'A 区',
          workContent: '检查',
          photographer: '张工',
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        ),
      );
      final collisionService = CaptureTemplateService(
        database: database,
        idGenerator: () => 'colliding-id',
      );

      await expectLater(
        collisionService.create(
          projectId: 'project-1',
          name: 'Different template',
          workLocation: 'B 区',
          workContent: '复查',
          photographer: '李工',
        ),
        throwsA(isNot(isA<CaptureTemplateException>())),
      );
    });

    test(
      'counts supplementary-plane characters as one editable character',
      () async {
        final acceptedName = '\u{1F600}' * captureTemplateNameMaxLength;
        final acceptedLocation = '\u{1F600}' * captureTemplateLocationMaxLength;
        final acceptedContent = '\u{1F600}' * captureTemplateContentMaxLength;
        final acceptedPhotographer =
            '\u{1F600}' * captureTemplatePhotographerMaxLength;
        final rejectedName = '\u{1F600}' * (captureTemplateNameMaxLength + 1);

        expect(
          (await service.create(
            projectId: 'project-1',
            name: acceptedName,
            workLocation: acceptedLocation,
            workContent: acceptedContent,
            photographer: acceptedPhotographer,
          )).name,
          acceptedName,
        );
        await expectFailure(
          () => service.create(
            projectId: 'project-1',
            name: rejectedName,
            workLocation: 'B 区',
            workContent: '复查',
            photographer: '李工',
          ),
          CaptureTemplateFailure.nameTooLong,
        );
      },
    );

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

class _InterleavingInsertDatabase extends AppDatabase {
  _InterleavingInsertDatabase(super.executor) : super.forTesting();

  CaptureTemplatesCompanion? insertBeforeNextTemplate;
  var countWasRead = false;
  var templatesWereRead = false;
  final events = <String>[];

  @override
  Future<int> countCaptureTemplates(String projectId) {
    countWasRead = true;
    events.add('count');
    return super.countCaptureTemplates(projectId);
  }

  @override
  Future<List<CaptureTemplate>> captureTemplatesForProject(String projectId) {
    templatesWereRead = true;
    events.add('templates');
    return super.captureTemplatesForProject(projectId);
  }

  @override
  Future<CaptureTemplate> insertCaptureTemplate(
    CaptureTemplatesCompanion row,
  ) async {
    final competing = insertBeforeNextTemplate;
    if (competing != null) {
      insertBeforeNextTemplate = null;
      events.add('conflict');
      await super.insertCaptureTemplate(competing);
    }
    return super.insertCaptureTemplate(row);
  }
}

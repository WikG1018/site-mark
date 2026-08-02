import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_template_rules.dart';
import 'package:uuid/uuid.dart';

enum CaptureTemplateFailure {
  emptyName,
  nameTooLong,
  emptyWorkLocation,
  workLocationTooLong,
  emptyWorkContent,
  workContentTooLong,
  emptyPhotographer,
  photographerTooLong,
  duplicateName,
  projectLimitReached,
  notFound,
}

class CaptureTemplateException implements Exception {
  const CaptureTemplateException(this.failure);

  final CaptureTemplateFailure failure;
}

class CaptureTemplateService {
  CaptureTemplateService({
    required this.database,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _idGenerator = idGenerator ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  Stream<List<CaptureTemplate>> watch(String projectId) =>
      database.watchCaptureTemplates(projectId);

  Future<CaptureTemplate> create({
    required String projectId,
    required String name,
    required String workLocation,
    required String workContent,
    required String photographer,
  }) async {
    final normalizedName = _validatedName(name);
    final normalizedLocation = _validatedField(
      workLocation,
      empty: CaptureTemplateFailure.emptyWorkLocation,
      tooLong: CaptureTemplateFailure.workLocationTooLong,
      maximumLength: captureTemplateLocationMaxLength,
    );
    final normalizedContent = _validatedField(
      workContent,
      empty: CaptureTemplateFailure.emptyWorkContent,
      tooLong: CaptureTemplateFailure.workContentTooLong,
      maximumLength: captureTemplateContentMaxLength,
    );
    final normalizedPhotographer = _validatedField(
      photographer,
      empty: CaptureTemplateFailure.emptyPhotographer,
      tooLong: CaptureTemplateFailure.photographerTooLong,
      maximumLength: captureTemplatePhotographerMaxLength,
    );
    final nameKey = captureTemplateNameKey(normalizedName);
    try {
      return await database.transaction(() async {
        if (await database.projectById(projectId) == null) {
          throw const CaptureTemplateException(CaptureTemplateFailure.notFound);
        }
        final templateCount = await database.countCaptureTemplates(projectId);
        if (templateCount >= captureTemplateLimitPerProject) {
          throw const CaptureTemplateException(
            CaptureTemplateFailure.projectLimitReached,
          );
        }
        final existing = await database.captureTemplatesForProject(projectId);
        if (existing.any((template) => template.nameKey == nameKey)) {
          throw const CaptureTemplateException(
            CaptureTemplateFailure.duplicateName,
          );
        }
        final timestamp = _clock();
        return database.insertCaptureTemplate(
          CaptureTemplatesCompanion.insert(
            id: _idGenerator(),
            projectId: projectId,
            name: normalizedName,
            nameKey: nameKey,
            workLocation: normalizedLocation,
            workContent: normalizedContent,
            photographer: normalizedPhotographer,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
      });
    } on CaptureTemplateException {
      rethrow;
    } catch (error) {
      if (_isTemplateNameUniquenessViolation(error)) {
        throw const CaptureTemplateException(
          CaptureTemplateFailure.duplicateName,
        );
      }
      rethrow;
    }
  }

  Future<CaptureTemplate> rename({
    required String projectId,
    required String templateId,
    required String name,
  }) async {
    final normalizedName = _validatedName(name);
    final nameKey = captureTemplateNameKey(normalizedName);
    try {
      return await database.transaction(() async {
        final existing = await database.captureTemplatesForProject(projectId);
        if (!existing.any((template) => template.id == templateId)) {
          throw const CaptureTemplateException(CaptureTemplateFailure.notFound);
        }
        if (existing.any(
          (template) =>
              template.id != templateId && template.nameKey == nameKey,
        )) {
          throw const CaptureTemplateException(
            CaptureTemplateFailure.duplicateName,
          );
        }
        return database.renameCaptureTemplate(
          id: templateId,
          projectId: projectId,
          name: normalizedName,
          nameKey: nameKey,
          updatedAt: _clock(),
        );
      });
    } on CaptureTemplateException {
      rethrow;
    } on StateError {
      throw const CaptureTemplateException(CaptureTemplateFailure.notFound);
    } catch (error) {
      if (_isTemplateNameUniquenessViolation(error)) {
        throw const CaptureTemplateException(
          CaptureTemplateFailure.duplicateName,
        );
      }
      rethrow;
    }
  }

  Future<void> delete({
    required String projectId,
    required String templateId,
  }) async {
    final deleted = await database.transaction(
      () =>
          database.deleteCaptureTemplate(id: templateId, projectId: projectId),
    );
    if (deleted != 1) {
      throw const CaptureTemplateException(CaptureTemplateFailure.notFound);
    }
  }

  String _validatedName(String value) => _validatedField(
    normalizeCaptureTemplateName(value),
    empty: CaptureTemplateFailure.emptyName,
    tooLong: CaptureTemplateFailure.nameTooLong,
    maximumLength: captureTemplateNameMaxLength,
  );

  String _validatedField(
    String value, {
    required CaptureTemplateFailure empty,
    required CaptureTemplateFailure tooLong,
    required int maximumLength,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw CaptureTemplateException(empty);
    if (normalized.length > maximumLength) {
      throw CaptureTemplateException(tooLong);
    }
    return normalized;
  }

  bool _isTemplateNameUniquenessViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('capture_templates');
  }
}

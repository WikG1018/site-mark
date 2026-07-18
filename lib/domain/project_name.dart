import 'package:sitemark/domain/photo_number.dart';

enum ProjectNameConflictKind { displayName, safeFileName }

class ProjectNameConflictException implements Exception {
  const ProjectNameConflictException(this.kind);

  final ProjectNameConflictKind kind;
}

/// Comparison key for names shown in the UI.
///
/// Leading/trailing whitespace, repeated whitespace, and English case do not
/// make a project name distinct.
String normalizedProjectNameKey(String name) {
  return name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

/// Comparison key for the project-name component used in new JPEG names.
String safeProjectFileNameKey(String name) {
  return safePhotoProjectName(name).toLowerCase();
}

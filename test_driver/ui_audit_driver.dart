import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final label = Platform.environment['SITEMARK_AUDIT_LABEL'] ?? 'default';
  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(label)) {
    throw ArgumentError('Invalid audit label');
  }
  final directory = Directory('.dart_tool/ui-audit/screenshots/$label');
  await directory.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) return false;
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}

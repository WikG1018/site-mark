import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

/// Device-only test, deliberately not part of `flutter test`.
/// Prepare a newer, same-debug-signed universal APK and mode.txt in this
/// test app's cache/sitemark-updates directory. Use only a disposable emulator.
/// mode.txt is "permission" before granting unknown-source access and "launch"
/// after granting it. No user data or production signing key is needed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native update verification and system installer handoff', (
    tester,
  ) async {
    final cache = await getTemporaryDirectory();
    final directory = Directory('${cache.path}/sitemark-updates');
    final apk = File('${directory.path}/sitemark-v1.0.32-universal.apk');
    expect(
      await apk.exists(),
      isTrue,
      reason: 'Prepare the isolated test APK first',
    );
    final mode = (await File(
      '${directory.path}/mode.txt',
    ).readAsString()).trim();
    expect(mode, isIn(['permission', 'launch']));
    final digest = await sha256.bind(apk.openRead()).first;
    final outcome = await AppUpdateApi().openInstaller(
      apk.path,
      digest.toString(),
      '1.0.32',
    );
    expect(
      outcome,
      mode == 'permission'
          ? ApkInstallOutcome.permissionRequired
          : ApkInstallOutcome.launched,
    );
  });
}

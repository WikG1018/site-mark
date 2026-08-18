import 'dart:io';

import 'package:path_provider/path_provider.dart';

const privacyConsentAcceptedKey = 'privacy_consent_accepted_v1';

abstract class PrivacyConsentStore {
  Future<bool> isAccepted();
  Future<void> accept();
}

class MemoryPrivacyConsentStore implements PrivacyConsentStore {
  MemoryPrivacyConsentStore({bool accepted = false}) : _accepted = accepted;

  bool _accepted;

  @override
  Future<bool> isAccepted() async => _accepted;

  @override
  Future<void> accept() async {
    _accepted = true;
  }
}

class FilePrivacyConsentStore implements PrivacyConsentStore {
  FilePrivacyConsentStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  Future<File> _file() async {
    final dir = _directory ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$privacyConsentAcceptedKey');
  }

  @override
  Future<bool> isAccepted() async {
    try {
      final file = await _file();
      if (!await file.exists()) return false;
      return (await file.readAsString()).trim() == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> accept() async {
    final file = await _file();
    await file.writeAsString('true', flush: true);
  }
}

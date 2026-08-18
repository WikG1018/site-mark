import 'dart:io';

bool get isOhosBuild =>
    const bool.fromEnvironment('SITEMARK_OHOS', defaultValue: false) ||
    Platform.operatingSystem == 'ohos';

bool rustInitFailed = false;

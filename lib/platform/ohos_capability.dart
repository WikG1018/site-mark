import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isOhosBuild =>
    const bool.fromEnvironment('SITEMARK_OHOS', defaultValue: false) ||
    Platform.operatingSystem == 'ohos';

final ValueNotifier<bool> rustInitFailedNotifier = ValueNotifier<bool>(false);

bool get rustInitFailed => rustInitFailedNotifier.value;

set rustInitFailed(bool value) {
  rustInitFailedNotifier.value = value;
}

bool useDegradedRustPipelines({
  required bool ohosBuild,
  required bool rustFailed,
}) => ohosBuild && rustFailed;

import 'package:flutter_riverpod/flutter_riverpod.dart';

final allCapturesSelectionModeProvider =
    NotifierProvider<AllCapturesSelectionModeController, bool>(
      AllCapturesSelectionModeController.new,
    );

/// Ephemeral root-chrome state shared by the records branch and root shell.
class AllCapturesSelectionModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool value) {
    if (state != value) state = value;
  }
}

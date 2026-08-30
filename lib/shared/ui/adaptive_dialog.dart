import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One structured action of an [showAppDialog] alert.
///
/// [result] is what the dialog future resolves to when the action pops it;
/// [onPressed] (if given) runs before the pop, so side effects like
/// `HapticFeedback` keep their existing order.
class AppDialogAction<T> {
  const AppDialogAction({
    required this.label,
    this.onPressed,
    this.result,
    this.isDefault = false,
    this.isDestructive = false,
    this.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final T? result;
  final bool isDefault;
  final bool isDestructive;
  final Key? key;
}

/// Shows a confirmation/alert dialog that follows the platform conventions:
/// a Material [AlertDialog] everywhere except iOS, which presents a
/// [CupertinoAlertDialog] per the Human Interface Guidelines.
///
/// The Android composition mirrors the call sites this helper replaced —
/// cancel and default actions are plain [TextButton]/[FilledButton] pairs,
/// destructive actions use the error color. The barrier stays tap-through
/// dismissible per the caller's existing semantics; this pass does not
/// tighten confirmation behavior.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  Widget? title,
  Widget? content,
  required List<AppDialogAction<T>> actions,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => buildAdaptiveAlertDialog<T>(
      dialogContext: dialogContext,
      title: title,
      content: content,
      actions: actions,
    ),
  );
}

/// Builds just the adaptive alert widget for call sites that own their
/// `showDialog` call (custom animation/route handling) but still want the
/// platform-convention composition. [dialogContext] is the dialog route's
/// context used to pop with the action result.
Widget buildAdaptiveAlertDialog<T>({
  required BuildContext dialogContext,
  Widget? title,
  Widget? content,
  required List<AppDialogAction<T>> actions,
}) {
  void popWith(AppDialogAction<T> action) {
    action.onPressed?.call();
    Navigator.of(dialogContext).pop(action.result);
  }

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoAlertDialog(
      title: title,
      content: content,
      actions: [
        for (final action in actions)
          CupertinoDialogAction(
            isDefaultAction: action.isDefault,
            isDestructiveAction: action.isDestructive,
            onPressed: () => popWith(action),
            child: Text(action.label),
          ),
      ],
    );
  }
  return AlertDialog(
    title: title,
    content: content,
    actions: [
      for (final action in actions)
        if (action.isDestructive)
          FilledButton(
            key: action.key,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => popWith(action),
            child: Text(action.label),
          )
        else if (action.isDefault)
          FilledButton(
            key: action.key,
            onPressed: () => popWith(action),
            child: Text(action.label),
          )
        else
          TextButton(
            key: action.key,
            onPressed: () => popWith(action),
            child: Text(action.label),
          ),
    ],
  );
}

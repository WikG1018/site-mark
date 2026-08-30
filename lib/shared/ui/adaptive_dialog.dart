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
    this.enabled = true,
    this.autoPop = true,
    this.child,
    this.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final T? result;
  final bool isDefault;
  final bool isDestructive;

  /// False disables the generated button (e.g. while an async delete runs);
  /// the pop still only happens through an enabled action.
  final bool enabled;

  /// Whether pressing the action closes the dialog automatically with
  /// [result]. Keep true for side-effect-only callbacks (haptics); set false
  /// when [onPressed] pops the route itself — e.g. a submit that pops only
  /// after successful validation.
  final bool autoPop;

  /// Optional custom button content (e.g. an inline progress spinner);
  /// falls back to [Text] of [label].
  final Widget? child;
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
  List<AppDialogAction<T>> actions = const [],
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
  List<AppDialogAction<T>> actions = const [],
}) {
  void popWith(AppDialogAction<T> action) {
    action.onPressed?.call();
    if (action.autoPop) {
      Navigator.of(dialogContext).pop(action.result);
    }
  }

  VoidCallback? resolveTap(AppDialogAction<T> action) =>
      action.enabled ? () => popWith(action) : null;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoAlertDialog(
      title: title,
      // Cupertino alerts provide no Material ancestor; Material form
      // controls inside (text fields) render corrupted without one.
      content: content == null
          ? null
          : Material(type: MaterialType.transparency, child: content),
      actions: [
        for (final action in actions)
          CupertinoDialogAction(
            isDefaultAction: action.isDefault,
            isDestructiveAction: action.isDestructive,
            onPressed: resolveTap(action),
            child: action.child ?? Text(action.label),
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
            onPressed: resolveTap(action),
            child: action.child ?? Text(action.label),
          )
        else if (action.isDefault)
          FilledButton(
            key: action.key,
            onPressed: resolveTap(action),
            child: action.child ?? Text(action.label),
          )
        else
          TextButton(
            key: action.key,
            onPressed: resolveTap(action),
            child: action.child ?? Text(action.label),
          ),
    ],
  );
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One row of an adaptive action sheet ([showAppActionSheet]).
class AppSheetAction<T> {
  const AppSheetAction({
    required this.label,
    this.result,
    this.icon,
    this.subtitle,
    this.isDestructive = false,
    this.enabled = true,
    this.checked = false,
    this.onPressed,
    this.key,
  });

  final String label;
  final T? result;

  /// Leading icon; used by the Material branch only — HIG action sheets are
  /// text-only, so iOS rows render the label alone.
  final IconData? icon;

  /// Secondary explanation line under [label] (Material rows and iOS rows).
  final String? subtitle;
  final bool isDestructive;
  final bool enabled;

  /// Renders a selection checkmark next to the row — for pick-one menus that
  /// show the active option (filter sheets).
  final bool checked;

  /// Runs before the sheet pops with [result].
  final VoidCallback? onPressed;
  final Key? key;
}

void _resolveAction<T>(AppSheetAction<T> action, BuildContext sheetContext) {
  action.onPressed?.call();
  Navigator.of(sheetContext).pop(action.result);
}

/// Cancel row label; apps ship Cupertino localizations, but tests and bare
/// Material harnesses may not, so fall back to Material's label.
String _cancelLabel(BuildContext sheetContext) {
  try {
    return CupertinoLocalizations.of(sheetContext).cancelButtonLabel;
  } on AssertionError catch (_) {
    return MaterialLocalizations.of(sheetContext).cancelButtonLabel;
  }
}

/// Shows a command menu following each platform's shape: a
/// [CupertinoActionSheet] over a dimmed page on iOS, a Material modal bottom
/// sheet with a drag handle everywhere else.
///
/// [title]/[message] render as the sheet header on both platforms. On iOS the
/// system cancel row is appended automatically; the Material sheet is
/// tap-outside dismissible instead, matching the pre-existing call sites.
Future<T?> showAppActionSheet<T>({
  required BuildContext context,
  String? title,
  String? message,
  required List<AppSheetAction<T>> actions,
  bool useRootNavigator = true,
  Key? sheetKey,
}) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return showCupertinoModalPopup<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          key: sheetKey,
          title: title == null ? null : Text(title),
          message: message == null ? null : Text(message),
          actions: [
            for (final action in actions)
              CupertinoActionSheetAction(
                key: action.key,
                onPressed: action.enabled
                    ? () => _resolveAction(action, sheetContext)
                    : () {},
                isDestructiveAction: action.isDestructive,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (action.checked) ...[
                          const Icon(
                            CupertinoIcons.checkmark,
                            size: 17,
                            color: CupertinoColors.activeBlue,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          action.label,
                          style: action.enabled
                              ? null
                              : const TextStyle(
                                  color: CupertinoColors.tertiaryLabel,
                                ),
                        ),
                      ],
                    ),
                    if (action.subtitle != null)
                      Text(
                        action.subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                  ],
                ),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(_cancelLabel(sheetContext)),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final errorColor = Theme.of(sheetContext).colorScheme.error;
      final hasHeader = title != null || message != null;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: SingleChildScrollView(
            key: sheetKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasHeader) ...[
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        title,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        message,
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                    ),
                ],
                for (final action in actions)
                  ListTile(
                    key: action.key,
                    enabled: action.enabled,
                    selected: action.checked,
                    leading: action.icon == null
                        ? null
                        : Icon(
                            action.icon,
                            color: action.isDestructive ? errorColor : null,
                          ),
                    title: Text(
                      action.label,
                      style: TextStyle(
                        color: action.isDestructive ? errorColor : null,
                      ),
                    ),
                    trailing: action.checked
                        ? Icon(
                            Icons.check,
                            color: Theme.of(sheetContext).colorScheme.primary,
                          )
                        : null,
                    subtitle: action.subtitle == null
                        ? null
                        : Text(action.subtitle!),
                    onTap: action.enabled
                        ? () => _resolveAction(action, sheetContext)
                        : null,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

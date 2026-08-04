import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';

/// Animated slot that hosts the [LocationPermissionPrompt] above the capture
/// form. The card expands and fades in when [prompt] arrives and collapses
/// back to zero height when it is removed, so the form below never jumps
/// while the explanation appears or is dismissed.
class LocationPermissionPromptArea extends StatelessWidget {
  const LocationPermissionPromptArea({super.key, this.prompt});

  /// The prompt to show, or `null` when the explanation should be hidden.
  final Widget? prompt;

  @override
  Widget build(BuildContext context) {
    final visible = prompt != null;
    final duration = AppMotion.durationOf(context, AppMotion.medium2);
    final child = visible
        ? Padding(padding: const EdgeInsets.only(bottom: 8), child: prompt)
        : const SizedBox(width: double.infinity);
    if (duration == Duration.zero) {
      return child;
    }
    return AnimatedSize(
      duration: duration,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: duration,
        curve: AppMotion.standard,
        opacity: visible ? 1 : 0,
        child: child,
      ),
    );
  }
}

/// Non-blocking explanation card rendered above the capture form whenever the
/// host location permission is not granted and the user has not dismissed the
/// prompt.
///
/// The card never requests a runtime permission itself. Tapping the
/// call-to-action surfaces [onEnable]; the owning screen decides whether to
/// call `LocationPermissionService.request` or `openSettings` based on
/// [openSettings]. Tapping the close icon surfaces [onDismiss] so the screen
/// can persist the dismissal flag.
class LocationPermissionPrompt extends StatelessWidget {
  const LocationPermissionPrompt({
    super.key,
    required this.onDismiss,
    required this.onEnable,
    required this.openSettings,
  });

  final VoidCallback onDismiss;
  final VoidCallback onEnable;

  /// When `true` the platform no longer allows an in-app permission request,
  /// so the call-to-action switches from "Enable location" to "Open settings".
  final bool openSettings;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Row(
      key: const Key('location-permission-prompt'),
      children: [
        const Icon(Icons.location_on_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            strings.locationPermissionExplanation,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          key: const Key('location-permission-enable'),
          onPressed: onEnable,
          child: Text(
            openSettings ? strings.openSettingsLabel : strings.enableLocation,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          key: const Key('location-permission-dismiss'),
          icon: const Icon(Icons.close),
          onPressed: onDismiss,
          tooltip: strings.dismiss,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';

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
    return Card(
      key: const Key('location-permission-prompt'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(strings.locationPermissionExplanation)),
                IconButton(
                  key: const Key('location-permission-dismiss'),
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                  tooltip: strings.dismiss,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              key: const Key('location-permission-enable'),
              onPressed: onEnable,
              icon: const Icon(Icons.location_searching),
              label: Text(
                openSettings
                    ? strings.openSettingsLabel
                    : strings.enableLocation,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

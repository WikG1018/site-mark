import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/app_update_controller.dart';

class AppUpdatePanel extends StatelessWidget {
  const AppUpdatePanel({
    super.key,
    required this.controller,
    required this.mode,
    this.available,
  });
  final AppUpdateController controller;
  final ReleaseCheckMode mode;
  final ReleaseDownload? available;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final asset = available ?? controller.download;
        if (asset == null) return const SizedBox.shrink();
        final current = controller.download?.tag == asset.tag;
        final phase = current ? controller.phase : AppUpdatePhase.idle;
        final downloading = phase == AppUpdatePhase.downloading;
        final canInstall = current && controller.readyPath != null;
        final busy = controller.busy;
        final percent = ((controller.progress ?? 0) * 100).round();
        final size = (asset.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
        final message = switch (phase) {
          AppUpdatePhase.downloading =>
            '$percent% · ${(controller.receivedBytes / (1024 * 1024)).toStringAsFixed(1)} / $size MB',
          AppUpdatePhase.verifying => strings.updateVerifying,
          AppUpdatePhase.installing => strings.updateInstalling,
          AppUpdatePhase.ready => strings.updateReady,
          AppUpdatePhase.permissionRequired => strings.updatePermissionNote,
          AppUpdatePhase.cancelled => strings.updateCancelled,
          AppUpdatePhase.failed => switch (controller.failure) {
            AppUpdateFailure.integrity => strings.updateIntegrityFailed,
            AppUpdateFailure.storage => strings.updateStorageFailed,
            AppUpdateFailure.installation => strings.updateInstallationFailed,
            _ => strings.updateNetworkFailed,
          },
          AppUpdatePhase.idle =>
            '$size MB · ${asset.variant.name == 'arm64' ? 'ARM64' : strings.updateUniversal}',
        };
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.newVersionFound(asset.tag.substring(1)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                key: const Key('update-status'),
                style: TextStyle(
                  color: phase == AppUpdatePhase.failed
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              if (downloading || phase == AppUpdatePhase.verifying) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  key: const Key('update-download-progress'),
                  value: downloading ? controller.progress : null,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!busy)
                    FilledButton.icon(
                      key: const Key('download-update'),
                      icon: Icon(
                        canInstall
                            ? Icons.system_update
                            : Icons.download_outlined,
                      ),
                      label: Text(
                        canInstall
                            ? strings.installUpdate
                            : strings.downloadUpdate,
                      ),
                      onPressed: () => unawaited(
                        _startOrInstall(context, asset, canInstall),
                      ),
                    ),
                  if (downloading || phase == AppUpdatePhase.verifying)
                    TextButton(
                      key: const Key('cancel-update-download'),
                      onPressed: controller.cancel,
                      child: Text(strings.cancel),
                    ),
                  if (phase == AppUpdatePhase.permissionRequired)
                    OutlinedButton(
                      key: const Key('allow-update-installation'),
                      onPressed: () =>
                          unawaited(controller.openPermissionSettings()),
                      child: Text(strings.updatePermissionAction),
                    ),
                  if (phase == AppUpdatePhase.failed && canInstall)
                    TextButton(
                      onPressed: () =>
                          unawaited(_startOrInstall(context, asset, false)),
                      child: Text(strings.downloadUpdate),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                strings.updateDownloadNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startOrInstall(
    BuildContext context,
    ReleaseDownload asset,
    bool canInstall,
  ) async {
    if (canInstall) {
      await controller.install();
      return;
    }
    await controller.start(asset, mode);
    if (context.mounted &&
        controller.phase == AppUpdatePhase.ready &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await controller.install();
    }
  }
}

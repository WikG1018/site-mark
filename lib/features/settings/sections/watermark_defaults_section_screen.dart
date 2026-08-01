// lib/features/settings/sections/watermark_defaults_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/theme/accent_choice_chip.dart';
import 'package:sitemark/shared/theme/accent_swatches.dart';

class WatermarkDefaultsSectionScreen extends ConsumerStatefulWidget {
  const WatermarkDefaultsSectionScreen({super.key});

  @override
  ConsumerState<WatermarkDefaultsSectionScreen> createState() =>
      _WatermarkDefaultsSectionScreenState();
}

class _WatermarkDefaultsSectionScreenState
    extends ConsumerState<WatermarkDefaultsSectionScreen> {
  double? _dragValue;
  double? _fontScaleDragValue;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final asyncSettings = ref.watch(appSettingControllerProvider);
    final settings = asyncSettings.value;
    if (settings == null) {
      return SettingsSectionScaffold(
        title: strings.newProjectDefaults,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.newProjectDefaults,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Position
          Text(
            strings.watermarkPosition,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('default-position-segmented'),
            style: segmentTapTargetStyle,
            segments: [
              ButtonSegment(
                value: 'bottomLeft',
                label: Text(
                  strings.bottomLeft,
                  key: const Key('default-position-bottomLeft'),
                ),
              ),
              ButtonSegment(
                value: 'bottomRight',
                label: Text(
                  strings.bottomRight,
                  key: const Key('default-position-bottomRight'),
                ),
              ),
            ],
            selected: {settings.defaultWatermarkPosition},
            onSelectionChanged: (selection) => ref
                .read(appSettingControllerProvider.notifier)
                .update(
                  (s) => s.copyWith(defaultWatermarkPosition: selection.single),
                ),
          ),
          const SizedBox(height: 24),
          // Opacity slider (migrate _dragValue logic)
          Builder(
            builder: (context) {
              final opacity = (_dragValue ?? settings.defaultWatermarkOpacity)
                  .clamp(0.20, 0.95);
              final percent = (opacity * 100).round();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.watermarkOpacity,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text('$percent%'),
                    ],
                  ),
                  Slider(
                    key: const Key('opacity-slider'),
                    value: opacity,
                    min: 0.20,
                    max: 0.95,
                    divisions: 75,
                    label: '$percent%',
                    onChanged: (value) => setState(() => _dragValue = value),
                    onChangeEnd: (value) {
                      ref
                          .read(appSettingControllerProvider.notifier)
                          .update(
                            (s) => s.copyWith(defaultWatermarkOpacity: value),
                          );
                      setState(() => _dragValue = null);
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            strings.opacityHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          // Font scale slider (migrate _fontScaleDragValue logic)
          Builder(
            builder: (context) {
              final fontScale =
                  (_fontScaleDragValue ?? settings.defaultWatermarkFontScale)
                      .clamp(0.80, 1.60);
              final percent = (fontScale * 100).round();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.watermarkFontSize,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text('$percent%'),
                    ],
                  ),
                  Slider(
                    key: const Key('default-font-scale-slider'),
                    value: fontScale,
                    min: 0.80,
                    max: 1.60,
                    divisions: 16,
                    label: '$percent%',
                    onChanged: (value) =>
                        setState(() => _fontScaleDragValue = value),
                    onChangeEnd: (value) {
                      ref
                          .read(appSettingControllerProvider.notifier)
                          .update(
                            (s) => s.copyWith(defaultWatermarkFontScale: value),
                          );
                      setState(() => _fontScaleDragValue = null);
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            strings.fontScaleHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          // Accent color
          Text(
            strings.accentColor,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final swatch in accentSwatches)
                AccentChoiceChip(
                  key: swatch.key,
                  argb: swatch.argb,
                  label: accentLabel(strings, swatch.argb),
                  selected:
                      settings.defaultWatermarkAccentColorArgb == swatch.argb,
                  onSelected: () => ref
                      .read(appSettingControllerProvider.notifier)
                      .update(
                        (s) => s.copyWith(
                          defaultWatermarkAccentColorArgb: swatch.argb,
                        ),
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

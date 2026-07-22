import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';

class ProjectWatermarkSettingsScreen extends ConsumerStatefulWidget {
  const ProjectWatermarkSettingsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectWatermarkSettingsScreen> createState() =>
      _ProjectWatermarkSettingsScreenState();
}

class _ProjectWatermarkSettingsScreenState
    extends ConsumerState<ProjectWatermarkSettingsScreen> {
  String? _position;
  double? _opacity;
  int? _accentColorArgb;
  double? _fontScale;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.projectWatermarkSettings)),
      body: FutureBuilder<Project?>(
        future: database.projectById(widget.projectId),
        builder: (context, snapshot) {
          final project = snapshot.data;
          if (project == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _position ??= project.watermarkPosition;
          _opacity ??= project.watermarkOpacity;
          _accentColorArgb ??= project.watermarkAccentColorArgb;
          _fontScale ??= project.watermarkFontScale;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                strings.watermarkPreviewTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    key: const Key('watermark-preview'),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8D9AA5), Color(0xFF4E5A65)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _PreviewGridPainter()),
                        ),
                        AnimatedOpacity(
                          key: const Key('watermark-preview-opacity'),
                          opacity: _opacity!,
                          duration: AppMotion.short4,
                          child: Align(
                            alignment: _position == 'bottomRight'
                                ? Alignment.bottomRight
                                : Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: _WatermarkPreviewCard(
                                accentColor: Color(_accentColorArgb!),
                                fontScale: _fontScale!,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                strings.watermarkSettingsHint,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              Text(
                strings.watermarkPosition,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'bottomLeft',
                    icon: const Icon(Icons.align_horizontal_left),
                    label: Text(strings.bottomLeft),
                  ),
                  ButtonSegment(
                    value: 'bottomRight',
                    icon: const Icon(Icons.align_horizontal_right),
                    label: Text(strings.bottomRight),
                  ),
                ],
                selected: {_position!},
                onSelectionChanged: (selection) {
                  setState(() => _position = selection.single);
                },
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.watermarkOpacity,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('${(_opacity! * 100).round()}%'),
                ],
              ),
              Slider(
                value: _opacity!,
                min: 0.2,
                max: 0.95,
                divisions: 15,
                label: '${(_opacity! * 100).round()}%',
                onChanged: (value) => setState(() => _opacity = value),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.watermarkFontSize,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('${(_fontScale! * 100).round()}%'),
                ],
              ),
              Slider(
                key: const Key('project-font-scale-slider'),
                value: _fontScale!,
                min: 0.80,
                max: 1.60,
                divisions: 16,
                label: '${(_fontScale! * 100).round()}%',
                onChanged: (value) => setState(() => _fontScale = value),
              ),
              const SizedBox(height: 20),
              Text(
                strings.accentColor,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AccentChoice(
                    choiceKey: const Key('accent-green'),
                    colorArgb: 0xff37c58b,
                    label: strings.green,
                    selected: _accentColorArgb == 0xff37c58b,
                    onSelected: () =>
                        setState(() => _accentColorArgb = 0xff37c58b),
                  ),
                  _AccentChoice(
                    choiceKey: const Key('accent-blue'),
                    colorArgb: 0xff1565c0,
                    label: strings.blue,
                    selected: _accentColorArgb == 0xff1565c0,
                    onSelected: () =>
                        setState(() => _accentColorArgb = 0xff1565c0),
                  ),
                  _AccentChoice(
                    choiceKey: const Key('accent-orange'),
                    colorArgb: 0xffef6c00,
                    label: strings.orange,
                    selected: _accentColorArgb == 0xffef6c00,
                    onSelected: () =>
                        setState(() => _accentColorArgb = 0xffef6c00),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(database),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(strings.save),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(AppDatabase database) async {
    setState(() => _saving = true);
    try {
      await database.updateProjectWatermarkSettings(
        projectId: widget.projectId,
        position: _position!,
        opacity: _opacity!,
        accentColorArgb: _accentColorArgb!,
        fontScale: _fontScale!,
      );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _WatermarkPreviewCard extends StatelessWidget {
  const _WatermarkPreviewCard({
    required this.accentColor,
    required this.fontScale,
  });

  final Color accentColor;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 11 * fontScale,
      height: 1.4,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SM-2026-0001',
            style: baseStyle.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text('2026-07-21 10:24', style: baseStyle),
          Text('31.2304°N 121.4737°E', style: baseStyle),
        ],
      ),
    );
  }
}

class _PreviewGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    const step = 24.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AccentChoice extends StatelessWidget {
  const _AccentChoice({
    required this.choiceKey,
    required this.colorArgb,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Key choiceKey;
  final int colorArgb;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      key: choiceKey,
      selected: selected,
      avatar: CircleAvatar(backgroundColor: Color(colorArgb)),
      label: Text(label),
      onSelected: (_) => onSelected(),
    );
  }
}

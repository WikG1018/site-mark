import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        GlassSurface(
          child: Material(
            color: Colors.transparent,
            child: Column(children: _withDividers(children)),
          ),
        ),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> entries) {
    return [
      for (final (index, entry) in entries.indexed) ...[
        if (index > 0) const Divider(height: 1, indent: 56),
        entry,
      ],
    ];
  }
}

class SettingsEntry extends StatelessWidget {
  const SettingsEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.route,
    this.subtitle,
    this.reserveSubtitleSpace = false,
  });

  final IconData icon;
  final String title;
  final String route;
  final String? subtitle;
  final bool reserveSubtitleSpace;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 48,
      leading: Icon(icon),
      title: Text(title),
      subtitle: switch (subtitle) {
        final value? => Text(value),
        null when reserveSubtitleSpace => const ExcludeSemantics(
          child: Text(' '),
        ),
        null => null,
      },
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}

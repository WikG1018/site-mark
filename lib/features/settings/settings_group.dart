import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// First-level boolean toggle: no secondary page, no chevron.
class SettingsSwitchEntry extends StatelessWidget {
  const SettingsSwitchEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      minTileHeight: 48,
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      // Every switch flip ticks (MiHaptic transient language): settings
      // toggles were the quietest controls in the app.
      onChanged: enabled && onChanged != null
          ? (next) {
              HapticFeedback.lightImpact();
              onChanged!(next);
            }
          : null,
    );
  }
}

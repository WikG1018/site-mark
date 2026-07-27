// lib/shared/theme/accent_swatches.dart
import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Accent swatches offered as new-project watermark defaults AND app theme
/// seed colors. Each entry carries a stable [Key] for test discovery.
///
/// Label resolution is handled by [accentLabel], which is the single source
/// of truth for mapping ARGB → localized name. Adding a new swatch requires
/// updating both this list and [_accentLabelMap]; the debug assertion in
/// [accentLabel] and [debugAssertAccentSwatchesComplete] catch omissions.
const accentSwatches = <({int argb, Key key})>[
  (argb: 0xff37c58b, key: Key('accent-green')),
  (argb: 0xff1565c0, key: Key('accent-blue')),
  (argb: 0xffef6c00, key: Key('accent-orange')),
  (argb: 0xffc62828, key: Key('accent-red')),
  (argb: 0xff6a1b9a, key: Key('accent-purple')),
  (argb: 0xff00838f, key: Key('accent-teal')),
  (argb: 0xffad1457, key: Key('accent-pink')),
  (argb: 0xfff9a825, key: Key('accent-yellow')),
  (argb: 0xff283593, key: Key('accent-indigo')),
];

/// Localized label resolver for each swatch ARGB. Keyed by ARGB so the
/// swatch record does not need to carry a string identifier that could
/// drift from this map.
final _accentLabelMap = <int, String Function(AppStrings)>{
  0xff37c58b: (s) => s.green,
  0xff1565c0: (s) => s.blue,
  0xffef6c00: (s) => s.orange,
  0xffc62828: (s) => s.red,
  0xff6a1b9a: (s) => s.purple,
  0xff00838f: (s) => s.teal,
  0xffad1457: (s) => s.pink,
  0xfff9a825: (s) => s.yellow,
  0xff283593: (s) => s.indigo,
};

/// Maps a swatch ARGB value to its localized label.
///
/// In debug mode, asserts that [argb] is a known swatch. Returns the empty
/// string in release mode for unknown values (should never happen for the
/// internal [accentSwatches] constants).
String accentLabel(AppStrings strings, int argb) {
  final resolver = _accentLabelMap[argb];
  assert(
    resolver != null,
    'Unknown accent ARGB: $argb. Add it to both accentSwatches and '
    '_accentLabelMap in lib/shared/theme/accent_swatches.dart.',
  );
  return resolver?.call(strings) ?? '';
}

/// Debug-only validation that every [accentSwatches] entry has a matching
/// label resolver in [_accentLabelMap]. Call from tests to catch drift.
bool debugAssertAccentSwatchesComplete() {
  assert(() {
    for (final swatch in accentSwatches) {
      assert(
        _accentLabelMap.containsKey(swatch.argb),
        'accentSwatches entry ${swatch.key} (ARGB ${swatch.argb}) has no '
        'label in _accentLabelMap. Add a matching entry.',
      );
    }
    return true;
  }());
  return true;
}

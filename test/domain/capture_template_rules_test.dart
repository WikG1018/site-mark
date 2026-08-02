import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_template_rules.dart';

import '../support/capture_template_contract_fixtures.dart';

void main() {
  test('normalizes template names and derives stable ASCII-only keys', () {
    for (final fixture in captureTemplateNameContractCases) {
      expect(
        normalizeCaptureTemplateName(fixture.input),
        fixture.normalized,
        reason: fixture.label,
      );
      expect(
        captureTemplateNameKey(fixture.input),
        fixture.key,
        reason: fixture.label,
      );
    }
    expect(captureTemplate80Scalars.runes.length, 80);
    expect(captureTemplate81Scalars.runes.length, 81);
  });

  test('locks Dart trim and RegExp whitespace sets used by template names', () {
    final whitespace = RegExp(r'^\s$');
    for (final (character, dartTrim, dartRegExp) in [
      ('\u0009', true, true),
      ('\u000A', true, true),
      ('\u000B', true, true),
      ('\u000C', true, true),
      ('\u000D', true, true),
      ('\u001C', false, false),
      ('\u0020', true, true),
      ('\u0085', true, false),
      ('\u00A0', true, true),
      ('\u1680', true, true),
      ('\u180E', false, false),
      ('\u2000', true, true),
      ('\u200A', true, true),
      ('\u200B', false, false),
      ('\u2028', true, true),
      ('\u2029', true, true),
      ('\u202F', true, true),
      ('\u205F', true, true),
      ('\u3000', true, true),
      ('\uFEFF', true, true),
    ]) {
      expect(
        character.trim().isEmpty,
        dartTrim,
        reason: character.runes.first.toRadixString(16),
      );
      expect(
        whitespace.hasMatch(character),
        dartRegExp,
        reason: character.runes.first.toRadixString(16),
      );
    }
  });

  test('normalizes edge whitespace before collapsing internal RegExp runs', () {
    for (final (input, normalized, key) in [
      (' \t\r\n\u000CA \t\r\n\u000CB \t\r\n\u000C', 'A B', 'a b'),
      ('\u00A0A\u1680\u2028\u202F\u205F\u3000B\u00A0', 'A B', 'a b'),
    ]) {
      expect(normalizeCaptureTemplateName(input), normalized);
      expect(captureTemplateNameKey(input), key);
    }
  });
}

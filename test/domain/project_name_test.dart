import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/project_name.dart';

void main() {
  test('normalizes whitespace and English case for display-name conflicts', () {
    expect(normalizedProjectNameKey(' Cloud   Site '), 'cloud site');
    expect(
      normalizedProjectNameKey(' CLOUD SITE '),
      normalizedProjectNameKey('cloud site'),
    );
  });

  test('normalizes unsafe filename characters for file-key conflicts', () {
    expect(safeProjectFileNameKey('A/B'), safeProjectFileNameKey('A:B'));
  });
}

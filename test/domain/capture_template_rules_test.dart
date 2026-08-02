import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_template_rules.dart';

void main() {
  test('normalizes template names and derives stable ASCII-only keys', () {
    expect(normalizeCaptureTemplateName('  日常   巡检  '), '日常 巡检');
    expect(captureTemplateNameKey('  AbC  '), 'abc');
    expect(captureTemplateNameKey('模板A'), '模板a');
  });
}

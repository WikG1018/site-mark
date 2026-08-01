import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';

void main() {
  test('normalizes whitespace and keeps literal wildcard characters', () {
    expect(normalizeCaptureSearchTerms('  21栋   巡检  '), ['21栋', '巡检']);
    expect(normalizeCaptureSearchTerms(r'100% A_B\C'), [r'100%', r'A_B\C']);
  });

  test('query equality includes filter and normalized text', () {
    const a = CaptureListQuery(
      filter: CaptureFilter(projectId: 'p1', year: 2026),
      searchText: '  风管 ',
    );
    const b = CaptureListQuery(
      filter: CaptureFilter(projectId: 'p1', year: 2026),
      searchText: '风管',
    );
    expect(a.normalizedTerms, b.normalizedTerms);
  });
}

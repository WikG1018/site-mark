import 'capture_filter.dart';

typedef CapturePageCursor = ({DateTime sortTime, String id});

final class CaptureDateOptions {
  const CaptureDateOptions({
    this.years = const [],
    this.months = const [],
    this.days = const [],
  });

  final List<int> years;
  final List<int> months;
  final List<int> days;
}

final class CaptureListQuery {
  const CaptureListQuery({
    this.filter = const CaptureFilter(),
    this.searchText = '',
  });

  final CaptureFilter filter;
  final String searchText;

  List<String> get normalizedTerms => normalizeCaptureSearchTerms(searchText);

  CaptureListQuery copyWith({CaptureFilter? filter, String? searchText}) =>
      CaptureListQuery(
        filter: filter ?? this.filter,
        searchText: searchText ?? this.searchText,
      );
}

List<String> normalizeCaptureSearchTerms(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((term) => term.isNotEmpty)
    .toList(growable: false);

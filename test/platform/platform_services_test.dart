import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/platform_services.dart';

void main() {
  test('parses stable Rust image error prefixes', () {
    expect(
      ImagePipelineException.tryParseRustError('not_found:open original'),
      isA<ImagePipelineException>().having(
        (error) => error.kind,
        'kind',
        ImagePipelineFailureKind.notFound,
      ),
    );
    expect(
      ImagePipelineException.tryParseRustError('io:write output'),
      isA<ImagePipelineException>().having(
        (error) => error.kind,
        'kind',
        ImagePipelineFailureKind.transientIo,
      ),
    );
    expect(
      ImagePipelineException.tryParseRustError('invalid_data:decode jpeg'),
      isA<ImagePipelineException>().having(
        (error) => error.kind,
        'kind',
        ImagePipelineFailureKind.invalidData,
      ),
    );
    expect(ImagePipelineException.tryParseRustError('unknown'), isNull);
  });
}

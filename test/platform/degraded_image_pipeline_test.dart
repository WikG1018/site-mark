import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/degraded_image_pipeline.dart';
import 'package:sitemark/platform/platform_services.dart';

void main() {
  test('degraded pipeline implements ImagePipeline and reports degraded', () {
    const pipeline = DegradedImagePipeline();
    expect(pipeline, isA<ImagePipeline>());
    expect(pipeline.isDegraded, isTrue);
  });
}

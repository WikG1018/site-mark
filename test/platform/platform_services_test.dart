import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

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

  group('PigeonPlatformServices bridge', () {
    test(
      'inspectImage delegates to the Pigeon API and returns the metadata',
      () async {
        final api = _FakeSystemApi();
        final services = PigeonPlatformServices(api: api);

        final result = await services.inspectImage('/photos/capture-1.jpg');

        expect(api.inspectedPath, '/photos/capture-1.jpg');
        expect(result.width, 640);
        expect(result.height, 480);
        expect(result.fileSizeBytes, 12345);
        expect(result.mimeType, 'image/jpeg');
      },
    );

    test(
      'getLocationPermissionState delegates and returns the state',
      () async {
        final api = _FakeSystemApi()
          ..locationPermissionState = LocationPermissionState.granted;
        final services = PigeonPlatformServices(api: api);

        expect(
          await services.getLocationPermissionState(),
          LocationPermissionState.granted,
        );
      },
    );

    test('requestLocationPermission delegates and returns the state', () async {
      final api = _FakeSystemApi()
        ..requestResult = LocationPermissionState.permanentlyDenied;
      final services = PigeonPlatformServices(api: api);

      expect(
        await services.requestLocationPermission(),
        LocationPermissionState.permanentlyDenied,
      );
    });

    test('openApplicationSettings delegates without error', () async {
      final api = _FakeSystemApi();
      final services = PigeonPlatformServices(api: api);

      await services.openApplicationSettings();

      expect(api.settingsOpened, isTrue);
    });
  });
}

class _FakeSystemApi extends SiteMarkSystemApi {
  LocationPermissionState locationPermissionState =
      LocationPermissionState.denied;
  LocationPermissionState requestResult = LocationPermissionState.denied;
  String? inspectedPath;
  ImageMetadataResult inspectResult = ImageMetadataResult(
    width: 640,
    height: 480,
    fileSizeBytes: 12345,
    mimeType: 'image/jpeg',
  );
  bool settingsOpened = false;

  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      locationPermissionState;

  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      requestResult;

  @override
  Future<void> openApplicationSettings() async {
    settingsOpened = true;
  }

  @override
  Future<ImageMetadataResult> inspectImage(String path) async {
    inspectedPath = path;
    return inspectResult;
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sitemark/platform/jpeg_gps.dart';

import 'jpeg_gps_support.dart';

void main() {
  test('parses camera-style DMS GPS into decimal degrees', () {
    final bytes = jpegWithDmsGps(latitude: 31.23, longitude: 121.47);
    final gps = readJpegGpsCoordinates(bytes);
    expect(gps, isNotNull);
    expect(gps!.latitude, closeTo(31.23, 0.0001));
    expect(gps.longitude, closeTo(121.47, 0.0001));
  });

  test('parses single-value decimal GPS from JPEG EXIF', () {
    final bytes = jpegWithDecimalGps(latitude: 31.23, longitude: 121.47);
    final gps = readJpegGpsCoordinates(bytes);
    expect(gps, isNotNull);
    expect(gps!.latitude, closeTo(31.23, 0.0001));
    expect(gps.longitude, closeTo(121.47, 0.0001));
  });

  test('south and west refs negate decimal degrees', () {
    final bytes = jpegWithDmsGps(latitude: -31.23, longitude: -121.47);
    final gps = readJpegGpsCoordinates(bytes);
    expect(gps!.latitude, closeTo(-31.23, 0.0001));
    expect(gps.longitude, closeTo(-121.47, 0.0001));
  });

  test('returns null when JPEG has no GPS IFD', () {
    final image = img.Image(width: 8, height: 8);
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    expect(readJpegGpsCoordinates(bytes), isNull);
  });

  test('readJpegGpsFromPath returns null for missing file', () async {
    expect(await readJpegGpsFromPath('/tmp/sitemark-missing-gps.jpg'), isNull);
  });

  test('readJpegGpsFromPath reads DMS GPS from disk', () async {
    final dir = await Directory.systemTemp.createTemp('sitemark-gps-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/shot.jpg');
    await file.writeAsBytes(
      jpegWithDmsGps(latitude: 31.23, longitude: 121.47),
    );
    final gps = await readJpegGpsFromPath(file.path);
    expect(gps!.latitude, closeTo(31.23, 0.0001));
    expect(gps.longitude, closeTo(121.47, 0.0001));
  });
}

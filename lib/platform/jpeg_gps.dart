import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class JpegGpsCoordinates {
  const JpegGpsCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

Future<JpegGpsCoordinates?> readJpegGpsFromPath(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    return readJpegGpsCoordinates(bytes);
  } catch (_) {
    return null;
  }
}

JpegGpsCoordinates? readJpegGpsCoordinates(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return readJpegGpsFromImage(decoded);
}

JpegGpsCoordinates? readJpegGpsFromImage(img.Image image) {
  final gps = image.exif.gpsIfd;
  final latitude = _dmsToDecimal(gps.data[0x0002], gps.data[0x0001]);
  final longitude = _dmsToDecimal(gps.data[0x0004], gps.data[0x0003]);
  if (latitude == null || longitude == null) return null;
  if (!latitude.isFinite || !longitude.isFinite) return null;
  if (latitude.abs() > 90 || longitude.abs() > 180) return null;
  return JpegGpsCoordinates(latitude: latitude, longitude: longitude);
}

double? _dmsToDecimal(img.IfdValue? dms, img.IfdValue? refValue) {
  if (dms == null || dms.length == 0) return null;
  double decimal;
  if (dms.length >= 3) {
    final degrees = dms.toDouble(0);
    final minutes = dms.toDouble(1);
    final seconds = dms.toDouble(2);
    if (!degrees.isFinite || !minutes.isFinite || !seconds.isFinite) {
      return null;
    }
    decimal = degrees + minutes / 60.0 + seconds / 3600.0;
  } else if (dms.length == 1) {
    decimal = dms.toDouble(0);
    if (!decimal.isFinite) return null;
  } else {
    return null;
  }
  final ref = refValue?.toString().trim().toUpperCase() ?? '';
  if (ref.startsWith('S') || ref.startsWith('W')) {
    decimal = -decimal.abs();
  } else if (ref.startsWith('N') || ref.startsWith('E')) {
    decimal = decimal.abs();
  }
  return decimal;
}

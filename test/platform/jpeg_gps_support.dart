import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image/src/util/rational.dart';

Uint8List jpegWithDecimalGps({
  required double latitude,
  required double longitude,
}) {
  final image = img.Image(width: 16, height: 16);
  image.exif.gpsIfd.setGpsLocation(
    latitude: latitude,
    longitude: longitude,
  );
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List jpegWithDmsGps({
  required double latitude,
  required double longitude,
}) {
  final image = img.Image(width: 16, height: 16);
  final gps = image.exif.gpsIfd;
  gps.data[0x0001] = img.IfdValueAscii(latitude < 0 ? 'S' : 'N');
  gps.data[0x0002] = img.IfdValueRational.list(_decimalToDms(latitude.abs()));
  gps.data[0x0003] = img.IfdValueAscii(longitude < 0 ? 'W' : 'E');
  gps.data[0x0004] = img.IfdValueRational.list(_decimalToDms(longitude.abs()));
  return Uint8List.fromList(img.encodeJpg(image));
}

List<Rational> _decimalToDms(double decimal) {
  final degrees = decimal.floor();
  final minutesFull = (decimal - degrees) * 60.0;
  final minutes = minutesFull.floor();
  final seconds = ((minutesFull - minutes) * 60.0 * 10000).round();
  return [
    Rational(degrees, 1),
    Rational(minutes, 1),
    Rational(seconds, 10000),
  ];
}

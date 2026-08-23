import { describe, expect, it } from '@ohos/hypium';
import { exifGpsReading, ExifGpsReading, FinalCaptureLocation, needsExifLookup,
  parseGpsCoordinate, resolveFinalCaptureLocation } from '../main/ets/shared/ExifLocationPolicy';

function closeEnough(actual: number | null, expected: number): boolean {
  return actual !== null && Math.abs(actual - expected) < 1e-9;
}

export default function exifLocationPolicyTest(): void {
  describe('ExifLocationPolicy', () => {
    it('parses DMS rationals into signed decimal degrees', 0, () => {
      const expected = 31 + 14 / 60 + 33.43 / 3600;
      expect(closeEnough(parseGpsCoordinate('31/1,14/1,3343/100', 'N'), expected)).assertTrue();
      expect(closeEnough(parseGpsCoordinate('121/1,15/1,0/1', 'E'), 121.25)).assertTrue();
      expect(closeEnough(parseGpsCoordinate('31/1,14/1,3343/100', 'S'), -expected)).assertTrue();
      expect(closeEnough(parseGpsCoordinate('121/1,15/1,0/1', 'w'), -121.25)).assertTrue();
    });

    it('accepts whole-number segments without denominators', 0, () => {
      expect(parseGpsCoordinate('31,0,0', 'N')).assertEqual(31);
      expect(parseGpsCoordinate('45/1,30', 'E')).assertEqual(45.5);
    });

    it('rejects malformed DMS values and unknown references', 0, () => {
      expect(parseGpsCoordinate('', 'N') === null).assertTrue();
      expect(parseGpsCoordinate('31/1', 'N') === null).assertTrue();
      expect(parseGpsCoordinate('31/1,14/1,0/1,5/1', 'N') === null).assertTrue();
      expect(parseGpsCoordinate('a/1,14/1,0/1', 'N') === null).assertTrue();
      expect(parseGpsCoordinate('-31/1,14/1,0/1', 'N') === null).assertTrue();
      expect(parseGpsCoordinate('31/1,14/1,0/1', '') === null).assertTrue();
      expect(parseGpsCoordinate('31/1,14/1,0/1', 'X') === null).assertTrue();
    });

    it('rejects zero denominators and non-finite components', 0, () => {
      expect(parseGpsCoordinate('31/0,14/1,0/1', 'N') === null).assertTrue();
      expect(parseGpsCoordinate('31/1,NaN,0/1', 'N') === null).assertTrue();
    });

    it('bounds latitude and longitude ranges when composing a reading', 0, () => {
      const north = exifGpsReading('90/1,0/1,0/1', 'N', '121/1,0/1,0/1', 'E');
      expect(north === null).assertFalse();
      expect(exifGpsReading('91/1,0/1,0/1', 'N', '121/1,0/1,0/1', 'E') === null).assertTrue();
      const west = exifGpsReading('31/1,0/1,0/1', 'N', '180/1,0/1,0/1', 'W');
      expect(west === null).assertFalse();
      expect(exifGpsReading('31/1,0/1,0/1', 'N', '181/1,0/1,0/1', 'W') === null).assertTrue();
    });

    it('builds a reading only when both axes resolve', 0, () => {
      const both = exifGpsReading('31/1,0/1,0/1', 'N', '121/1,0/1,0/1', 'E');
      if (both === null) {
        expect(true).assertFalse();
        return;
      }
      expect(both.latitude).assertEqual(31);
      expect(both.longitude).assertEqual(121);
      expect(exifGpsReading('', '', '121/1,0/1,0/1', 'E') === null).assertTrue();
      expect(exifGpsReading('31/1,0/1,0/1', 'N', '', '') === null).assertTrue();
    });

    it('requests an EXIF lookup until the record already came from EXIF', 0, () => {
      expect(needsExifLookup('resolved')).assertTrue();
      expect(needsExifLookup('')).assertTrue();
      expect(needsExifLookup('exif')).assertFalse();
    });

    it('prefers the EXIF fix over the capture-moment fix', 0, () => {
      const final = resolveFinalCaptureLocation(new ExifGpsReading(31, 121), 30, 120, 5,
        'resolved');
      expect(final.latitude).assertEqual(31);
      expect(final.longitude).assertEqual(121);
      expect(final.accuracyMeters === null).assertTrue();
      expect(final.resolution === 'exif').assertTrue();
    });

    it('keeps the capture-moment fix when EXIF is unavailable', 0, () => {
      const final = resolveFinalCaptureLocation(null, 30, 120, 5, 'resolved');
      expect(final.latitude).assertEqual(30);
      expect(final.longitude).assertEqual(120);
      expect(final.accuracyMeters).assertEqual(5);
      expect(final.resolution === 'resolved').assertTrue();
    });

    it('does not re-resolve records that already carry an EXIF fix', 0, () => {
      const final = resolveFinalCaptureLocation(new ExifGpsReading(31, 121), 30, 120, null,
        'exif');
      expect(final.latitude).assertEqual(30);
      expect(final.resolution === 'exif').assertTrue();
    });
  });
}

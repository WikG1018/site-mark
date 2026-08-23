export class ExifGpsReading {
  latitude: number;
  longitude: number;

  constructor(latitude: number, longitude: number) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

export class FinalCaptureLocation {
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  resolution: string;

  constructor(latitude: number | null, longitude: number | null, accuracyMeters: number | null,
    resolution: string) {
    this.latitude = latitude;
    this.longitude = longitude;
    this.accuracyMeters = accuracyMeters;
    this.resolution = resolution;
  }
}

function parseFiniteNumber(raw: string): number | null {
  if (raw.length === 0) {
    return null;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseRational(raw: string): number | null {
  const value = raw.trim();
  if (value.length === 0) {
    return null;
  }
  const separator = value.indexOf('/');
  if (separator < 0) {
    return parseFiniteNumber(value);
  }
  const numerator = parseFiniteNumber(value.substring(0, separator));
  const denominator = parseFiniteNumber(value.substring(separator + 1));
  if (numerator === null || denominator === null || denominator === 0) {
    return null;
  }
  return numerator / denominator;
}

export function parseGpsCoordinate(dms: string, ref: string): number | null {
  const parts = dms.split(',');
  if (parts.length !== 2 && parts.length !== 3) {
    return null;
  }
  const degrees = parseRational(parts[0]);
  const minutes = parseRational(parts[1]);
  if (degrees === null || minutes === null) {
    return null;
  }
  let seconds = 0;
  if (parts.length === 3) {
    const parsedSeconds = parseRational(parts[2]);
    if (parsedSeconds === null) {
      return null;
    }
    seconds = parsedSeconds;
  }
  if (degrees < 0 || minutes < 0 || seconds < 0) {
    return null;
  }
  const hemisphere = ref.trim().toUpperCase();
  let sign = 0;
  if (hemisphere === 'N' || hemisphere === 'E') {
    sign = 1;
  } else if (hemisphere === 'S' || hemisphere === 'W') {
    sign = -1;
  } else {
    return null;
  }
  return sign * (degrees + minutes / 60 + seconds / 3600);
}

export function exifGpsReading(latitudeDms: string, latitudeRef: string, longitudeDms: string,
  longitudeRef: string): ExifGpsReading | null {
  const latitude = parseGpsCoordinate(latitudeDms, latitudeRef);
  if (latitude === null || Math.abs(latitude) > 90) {
    return null;
  }
  const longitude = parseGpsCoordinate(longitudeDms, longitudeRef);
  if (longitude === null || Math.abs(longitude) > 180) {
    return null;
  }
  return new ExifGpsReading(latitude, longitude);
}

export function needsExifLookup(locationResolution: string): boolean {
  return locationResolution !== 'exif';
}

export function resolveFinalCaptureLocation(exif: ExifGpsReading | null, momentLatitude: number | null,
  momentLongitude: number | null, momentAccuracyMeters: number | null,
  currentResolution: string): FinalCaptureLocation {
  if (exif !== null && needsExifLookup(currentResolution)) {
    return new FinalCaptureLocation(exif.latitude, exif.longitude, null, 'exif');
  }
  return new FinalCaptureLocation(momentLatitude, momentLongitude, momentAccuracyMeters,
    currentResolution);
}

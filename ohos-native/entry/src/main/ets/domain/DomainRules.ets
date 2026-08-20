const JPEG_NAME_BYTE_LIMIT: number = 255;

export const CAPTURE_TEMPLATE_NAME_MAX_LENGTH: number = 80;
export const CAPTURE_TEMPLATE_LOCATION_MAX_LENGTH: number = 160;
export const CAPTURE_TEMPLATE_CONTENT_MAX_LENGTH: number = 240;
export const CAPTURE_TEMPLATE_PHOTOGRAPHER_MAX_LENGTH: number = 80;
export const CAPTURE_TEMPLATE_LIMIT_PER_PROJECT: number = 100;

function pad(value: number, width: number): string {
  return value.toString().padStart(width, '0');
}

function scalarAt(value: string, offset: number): number {
  const first = value.charCodeAt(offset);
  if (first >= 0xD800 && first <= 0xDBFF && offset + 1 < value.length) {
    const second = value.charCodeAt(offset + 1);
    if (second >= 0xDC00 && second <= 0xDFFF) {
      return ((first - 0xD800) * 0x400) + second - 0xDC00 + 0x10000;
    }
  }
  return first;
}

function scalarWidth(value: string, offset: number): number {
  const first = value.charCodeAt(offset);
  if (first >= 0xD800 && first <= 0xDBFF && offset + 1 < value.length) {
    const second = value.charCodeAt(offset + 1);
    if (second >= 0xDC00 && second <= 0xDFFF) {
      return 2;
    }
  }
  return 1;
}

function scalarUtf8Bytes(scalar: number): number {
  if (scalar <= 0x7F) {
    return 1;
  }
  if (scalar <= 0x7FF) {
    return 2;
  }
  if (scalar <= 0xFFFF) {
    return 3;
  }
  return 4;
}

export function utf8ByteLength(value: string): number {
  let result = 0;
  let offset = 0;
  while (offset < value.length) {
    result += scalarUtf8Bytes(scalarAt(value, offset));
    offset += scalarWidth(value, offset);
  }
  return result;
}

export function unicodeScalarLength(value: string): number {
  let count = 0;
  let offset = 0;
  while (offset < value.length) {
    count++;
    offset += scalarWidth(value, offset);
  }
  return count;
}

function trimToUtf8Bytes(value: string, maxBytes: number): string {
  let used = 0;
  let offset = 0;
  while (offset < value.length) {
    const bytes = scalarUtf8Bytes(scalarAt(value, offset));
    if (used + bytes > maxBytes) {
      break;
    }
    used += bytes;
    offset += scalarWidth(value, offset);
  }
  return value.substring(0, offset);
}

export function safePhotoProjectName(projectName: string, suffixReserve: number = 24): string {
  let safe = projectName.trim()
    .replace(/[\s~ \/\\:*?"<>|\u0000-\u001F\u007F-\u009F]+/g, '_')
    .replace(/_+/g, '_');
  const byteBudget = Math.max(1, JPEG_NAME_BYTE_LIMIT - suffixReserve);
  safe = trimToUtf8Bytes(safe, byteBudget)
    .replace(/^[._ ]+|[._ ]+$/g, '');
  return safe.length === 0 ? 'Project' : safe;
}

export function formatPhotoNumber(projectName: string, year: number, month: number,
  day: number, sequence: number): string {
  if (sequence < 1) {
    throw new Error('sequence must be positive');
  }
  const date = `${pad(year, 4)}${pad(month, 2)}${pad(day, 2)}`;
  const suffix = `-SM-${date}-${pad(sequence, 3)}.jpg`;
  const safe = safePhotoProjectName(projectName, utf8ByteLength(suffix));
  const number = `${safe}-SM-${date}-${pad(sequence, 3)}`;
  if (utf8ByteLength(`${number}.jpg`) > JPEG_NAME_BYTE_LIMIT) {
    throw new Error('generated JPEG name exceeds 255 UTF-8 bytes');
  }
  return number;
}

export function normalizedProjectNameKey(name: string): string {
  return name.trim().replace(/\s+/g, ' ').toLowerCase();
}

export function safeProjectFileNameKey(name: string): string {
  return safePhotoProjectName(name).toLowerCase();
}

export function normalizeCaptureTemplateName(value: string): string {
  return value.replace(/^[\s\u0085]+|[\s\u0085]+$/g, '').replace(/\s+/g, ' ');
}

export function captureTemplateNameKey(value: string): string {
  const normalized = normalizeCaptureTemplateName(value);
  let result = '';
  for (let index = 0; index < normalized.length; index++) {
    const codeUnit = normalized.charCodeAt(index);
    result += String.fromCharCode(codeUnit >= 0x41 && codeUnit <= 0x5A ? codeUnit + 0x20 : codeUnit);
  }
  return result;
}

export function normalizeCaptureSearchTerms(value: string): string[] {
  const normalized = value.trim();
  if (normalized.length === 0) {
    return [];
  }
  return normalized.split(/\s+/).filter((term: string): boolean => term.length > 0);
}

export function validateTemplateField(value: string, maxScalars: number): boolean {
  return value.indexOf('\u0000') < 0 && unicodeScalarLength(value) >= 1 &&
    unicodeScalarLength(value) <= maxScalars;
}

export function resolveWatermarkLocale(preferredLocale: string, systemLocale: string): string {
  const effective = preferredLocale.trim().length > 0 ? preferredLocale : systemLocale;
  return effective.toLowerCase().startsWith('en') ? 'en' : 'zh';
}

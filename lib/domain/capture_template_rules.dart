const captureTemplateNameMaxLength = 80;
const captureTemplateLocationMaxLength = 160;
const captureTemplateContentMaxLength = 240;
const captureTemplatePhotographerMaxLength = 80;
const captureTemplateLimitPerProject = 100;

enum CaptureSuggestionField { workLocation, workContent, photographer }

String normalizeCaptureTemplateName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String captureTemplateNameKey(String value) {
  final name = normalizeCaptureTemplateName(value);
  return String.fromCharCodes(
    name.codeUnits.map(
      (codeUnit) =>
          codeUnit >= 0x41 && codeUnit <= 0x5a ? codeUnit + 0x20 : codeUnit,
    ),
  );
}

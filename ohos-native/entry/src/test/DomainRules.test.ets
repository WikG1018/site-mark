import { describe, expect, it } from '@ohos/hypium';
import {
  captureTemplateNameKey,
  formatPhotoNumber,
  inspectCaptureFields,
  normalizeCaptureSearchTerms,
  normalizeCaptureTemplateName,
  normalizedProjectNameKey,
  resolveWatermarkLocale,
  safePhotoProjectName,
  safeProjectFileNameKey,
  utf8ByteLength,
  unicodeScalarLength
} from '../main/ets/domain/DomainRules';

export default function domainRulesTest(): void {
  describe('DomainRules', () => {
    it('formats project-prefixed global daily photo numbers', 0, () => {
      expect(formatPhotoNumber('云湖之城', 2026, 7, 17, 3))
        .assertEqual('云湖之城-SM-20260717-003');
    });

    it('rejects invalid sequences', 0, () => {
      let rejected = false;
      try {
        formatPhotoNumber('项目', 2026, 7, 17, 0);
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('sanitizes forbidden filename characters while preserving safe punctuation', 0, () => {
      expect(safePhotoProjectName('  A 区 / 风管::检查  ')).assertEqual('A_区_风管_检查');
      expect(safePhotoProjectName('A~B')).assertEqual('A_B');
      expect(safePhotoProjectName('东区厂房改造（一期）')).assertEqual('东区厂房改造（一期）');
      expect(safePhotoProjectName('A.B')).assertEqual('A.B');
      expect(safePhotoProjectName('--A')).assertEqual('--A');
      expect(safePhotoProjectName('C&D')).assertEqual('C&D');
      expect(safePhotoProjectName(' . / : ? _ ')).assertEqual('Project');
    });

    it('sanitizes controls and unicode whitespace consistently', 0, () => {
      expect(safePhotoProjectName('A\u0080B')).assertEqual('A_B');
      expect(safePhotoProjectName('A\u00A0B')).assertEqual('A_B');
      expect(safePhotoProjectName('A\u2003B')).assertEqual('A_B');
      expect(safePhotoProjectName('A\u2028B')).assertEqual('A_B');
      expect(safePhotoProjectName('A\uFEFFB')).assertEqual('A_B');
    });

    it('keeps generated JPEG names inside the 255-byte budget', 0, () => {
      const number = formatPhotoNumber('😀'.repeat(60), 2026, 7, 17, 1);
      expect(utf8ByteLength(`${number}.jpg`) <= 255).assertTrue();
    });

    it('normalizes project conflict keys in both display and file domains', 0, () => {
      expect(normalizedProjectNameKey(' Cloud   Site ')).assertEqual('cloud site');
      expect(safeProjectFileNameKey('A/B')).assertEqual(safeProjectFileNameKey('A:B'));
    });

    it('normalizes template names and only folds ASCII uppercase', 0, () => {
      expect(normalizeCaptureTemplateName('  日常   巡检  ')).assertEqual('日常 巡检');
      expect(captureTemplateNameKey('ABC')).assertEqual('abc');
      expect(captureTemplateNameKey('模板A')).assertEqual('模板a');
      expect(normalizeCaptureTemplateName('\u200BA\u200BB\u200B'))
        .assertEqual('\u200BA\u200BB\u200B');
    });

    it('normalizes capture fields once for camera, database, and restore boundaries', 0, () => {
      const fields = inspectCaptureFields('  😀  ', '  巡检  ', '  王工  ', '  备注  ');
      expect(fields.valid).assertTrue();
      expect(fields.location).assertEqual('😀');
      expect(fields.work).assertEqual('巡检');
      expect(fields.photographer).assertEqual('王工');
      expect(fields.notes).assertEqual('备注');
      expect(inspectCaptureFields('', '巡检', '王工', '').valid).assertFalse();
      expect(inspectCaptureFields('A', '巡检', `王\u0000工`, '').valid).assertFalse();
      expect(inspectCaptureFields('😀'.repeat(161), '巡检', '王工', '').valid).assertFalse();
      expect(inspectCaptureFields('A', '巡检', '王工', `备\u0000注`).valid).assertFalse();
    });

    it('counts Unicode scalars instead of UTF-16 code units', 0, () => {
      expect(unicodeScalarLength('😀'.repeat(80))).assertEqual(80);
      expect(unicodeScalarLength('😀'.repeat(81))).assertEqual(81);
    });

    it('normalizes search into literal AND terms', 0, () => {
      const terms = normalizeCaptureSearchTerms('  21栋   巡检  ');
      expect(terms.length).assertEqual(2);
      expect(terms[0]).assertEqual('21栋');
      expect(terms[1]).assertEqual('巡检');
      const literal = normalizeCaptureSearchTerms('100% A_B\\C');
      expect(literal[0]).assertEqual('100%');
      expect(literal[1]).assertEqual('A_B\\C');
    });

    it('resolves each new capture watermark language from app or system preference', 0, () => {
      expect(resolveWatermarkLocale('en', 'zh-CN')).assertEqual('en');
      expect(resolveWatermarkLocale('zh', 'en-US')).assertEqual('zh');
      expect(resolveWatermarkLocale('', 'en-US')).assertEqual('en');
      expect(resolveWatermarkLocale('', 'zh-CN')).assertEqual('zh');
    });
  });
}

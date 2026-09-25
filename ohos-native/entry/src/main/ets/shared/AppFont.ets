import { font } from '@kit.ArkUI';

/** Embedded MiSans subset (D-024 / spec §7). Registering makes the family
 * available; ArkUI has no global fontFamily setting, so surfaces opt in via
 * [AppFont.FAMILY] (Regular) or [AppFont.FAMILY_MEDIUM] (the bundled Medium
 * cut — engine weight synthesis applies otherwise). Failures fall back to
 * the system font silently; the license copy ships next to the files. */
export class AppFont {
  static readonly FAMILY: string = 'MiSans';
  static readonly FAMILY_MEDIUM: string = 'MiSans Medium';
  static readonly REGULAR_SRC: string = '/rawfile/font/MiSans-Regular.ttf';
  static readonly MEDIUM_SRC: string = '/rawfile/font/MiSans-Medium.ttf';

  /** Idempotent for this window stage; safe to call before loadContent. */
  static register(): void {
    try {
      font.registerFont({ familyName: AppFont.FAMILY, familySrc: AppFont.REGULAR_SRC });
      font.registerFont({ familyName: AppFont.FAMILY_MEDIUM, familySrc: AppFont.MEDIUM_SRC });
    } catch (_) {
      // The system font stays the fallback — typography must never block boot.
    }
  }
}

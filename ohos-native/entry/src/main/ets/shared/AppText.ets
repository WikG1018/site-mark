export class AppText {
  private static english: boolean = false;

  static apply(localeCode: string, systemLocale: string): void {
    const selected = localeCode.length > 0 ? localeCode : systemLocale;
    AppText.english = selected.toLowerCase().startsWith('en');
  }

  static isEnglish(): boolean {
    return AppText.english;
  }
}

export function tr(chinese: string, english: string): string {
  return AppText.isEnglish() ? english : chinese;
}

const USER_FACING_ERROR_NAME: string = 'UserFacingError';

/** Builds an Error whose message is final, localized copy ready to show. */
export function userFacingError(message: string): Error {
  const error = new Error(message);
  error.name = USER_FACING_ERROR_NAME;
  return error;
}

/**
 * Returns the message of an error created by [userFacingError], or the
 * generic fallback pair for anything else (native pipeline failures, internal
 * sentinels) so raw diagnostics never reach a user-visible surface.
 */
export function userFacingMessage(error: Object, chinese: string, english: string): string {
  const err = error as Error;
  return err.name === USER_FACING_ERROR_NAME && err.message.length > 0 ?
    err.message : tr(chinese, english);
}

/**
 * Returns [error] itself when it is user-facing copy, otherwise wraps the
 * generic fallback pair — used by service boundaries that must not let
 * unclassified failures cross toward a screen.
 */
export function ensureUserFacing(error: Object, chinese: string, english: string): Error {
  const err = error as Error;
  return err.name === USER_FACING_ERROR_NAME && err.message.length > 0 ?
    err : userFacingError(tr(chinese, english));
}

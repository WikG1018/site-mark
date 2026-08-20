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

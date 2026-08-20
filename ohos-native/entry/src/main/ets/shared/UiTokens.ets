export class UiTokens {
  static BACKGROUND: string = '#F5FAF6';
  static SURFACE: string = '#F9FCF9';
  static GLASS: string = '#ECF1F8F3';
  static GLASS_STRONG: string = '#F4F6FBF8';
  static PRIMARY: string = '#176B55';
  static PRIMARY_CONTAINER: string = '#C7F1DF';
  static TEXT: string = '#17201C';
  static TEXT_SECONDARY: string = '#526059';
  static OUTLINE: string = '#C7D4CC';
  static DANGER: string = '#B3261E';
  static SUCCESS: string = '#2E7D32';
  static WARNING: string = '#8A5A00';
  static CONTROL: string = '#E7EEE9';
  static ACCENT_SURFACE: string = '#E5F1EA';
  static DANGER_CONTAINER: string = '#FCE8E6';
  static DELETE_PANEL: string = '#FFF1F0';
  static DOCK: string = '#F2F7FBF8';
  static DOCK_SELECTED: string = '#B8C7F1DF';
  static readonly CARD_RADIUS: number = 24;
  static readonly CONTROL_RADIUS: number = 18;
  static readonly PAGE_PADDING: number = 20;

  static apply(dark: boolean, accentArgb: number): void {
    const accent = `#${(accentArgb >>> 0).toString(16).padStart(8, '0')}`;
    UiTokens.PRIMARY = accent;
    if (dark) {
      UiTokens.BACKGROUND = '#101512';
      UiTokens.SURFACE = '#171D19';
      UiTokens.GLASS = '#E0222A25';
      UiTokens.GLASS_STRONG = '#F02A332D';
      UiTokens.PRIMARY_CONTAINER = '#314E42';
      UiTokens.TEXT = '#E7EEE9';
      UiTokens.TEXT_SECONDARY = '#AAB8B0';
      UiTokens.OUTLINE = '#526159';
      UiTokens.DANGER = '#FFB4AB';
      UiTokens.SUCCESS = '#8BD69B';
      UiTokens.WARNING = '#F3C66F';
      UiTokens.CONTROL = '#253029';
      UiTokens.ACCENT_SURFACE = '#29463A';
      UiTokens.DANGER_CONTAINER = '#4A2522';
      UiTokens.DELETE_PANEL = '#3B201D';
      UiTokens.DOCK = '#E8202823';
      UiTokens.DOCK_SELECTED = '#80375648';
    } else {
      UiTokens.BACKGROUND = '#F5FAF6';
      UiTokens.SURFACE = '#F9FCF9';
      UiTokens.GLASS = '#ECF1F8F3';
      UiTokens.GLASS_STRONG = '#F4F6FBF8';
      UiTokens.PRIMARY_CONTAINER = '#C7F1DF';
      UiTokens.TEXT = '#17201C';
      UiTokens.TEXT_SECONDARY = '#526059';
      UiTokens.OUTLINE = '#C7D4CC';
      UiTokens.DANGER = '#B3261E';
      UiTokens.SUCCESS = '#2E7D32';
      UiTokens.WARNING = '#8A5A00';
      UiTokens.CONTROL = '#E7EEE9';
      UiTokens.ACCENT_SURFACE = '#E5F1EA';
      UiTokens.DANGER_CONTAINER = '#FCE8E6';
      UiTokens.DELETE_PANEL = '#FFF1F0';
      UiTokens.DOCK = '#F2F7FBF8';
      UiTokens.DOCK_SELECTED = '#B8C7F1DF';
    }
  }
}

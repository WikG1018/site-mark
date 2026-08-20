import { MotionPolicy } from './MotionPolicy';
import { UiTokens } from './UiTokens';

export class RootTabTransition {
  readonly changed: boolean;
  readonly targetIndex: number;
  readonly direction: number;
  readonly deferUntilSettled: boolean;

  constructor(changed: boolean, targetIndex: number, direction: number, deferUntilSettled: boolean = false) {
    this.changed = changed;
    this.targetIndex = targetIndex;
    this.direction = direction;
    this.deferUntilSettled = deferUntilSettled;
  }
}

export class RootMotionSpec {
  readonly pageDuration: number;
  readonly fadeDuration: number;
  readonly dockDuration: number;
  readonly enterX: number;
  readonly exitX: number;
  readonly dockBlur: number;
  readonly selectionBlur: number;

  constructor(pageDuration: number, fadeDuration: number, dockDuration: number,
    enterX: number, exitX: number, dockBlur: number, selectionBlur: number) {
    this.pageDuration = pageDuration;
    this.fadeDuration = fadeDuration;
    this.dockDuration = dockDuration;
    this.enterX = enterX;
    this.exitX = exitX;
    this.dockBlur = dockBlur;
    this.selectionBlur = selectionBlur;
  }
}

export class RootShellPolicy {
  private static readonly TAB_COUNT: number = 3;
  private static readonly DOCK_HORIZONTAL_MARGIN: number = 14;
  private static readonly DOCK_BOTTOM_MARGIN: number = 12;
  private static readonly ROOT_CONTENT_GAP: number = 28;
  private static readonly PAGE_ENTER_DISTANCE: number = 24;
  private static readonly PAGE_EXIT_DISTANCE: number = 16;
  private static readonly DOCK_BLUR: number = 24;
  private static readonly SELECTION_BLUR: number = 14;

  static clampTab(index: number): number {
    const safeIndex = Number.isFinite(index) ? Math.round(index) : 0;
    return Math.max(0, Math.min(RootShellPolicy.TAB_COUNT - 1, safeIndex));
  }

  static dockSelectedOffset(containerWidth: number, index: number): number {
    if (!Number.isFinite(containerWidth) || containerWidth <= 0) {
      return 0;
    }
    return containerWidth / RootShellPolicy.TAB_COUNT * RootShellPolicy.clampTab(index);
  }

  static transition(currentIndex: number, requestedIndex: number,
    animationPending: boolean = false): RootTabTransition {
    const current = RootShellPolicy.clampTab(currentIndex);
    const target = RootShellPolicy.clampTab(requestedIndex);
    if (current === target) {
      return new RootTabTransition(false, target, 0);
    }
    return new RootTabTransition(true, target, target > current ? 1 : -1, animationPending);
  }

  static motion(direction: number): RootMotionSpec {
    const normalizedDirection = direction > 0 ? 1 : (direction < 0 ? -1 : 0);
    const pageDuration = MotionPolicy.duration(UiTokens.MOTION_STANDARD);
    const displacementEnabled = !MotionPolicy.reduceMotion && normalizedDirection !== 0;
    return new RootMotionSpec(
      pageDuration,
      MotionPolicy.duration(UiTokens.MOTION_STANDARD),
      MotionPolicy.duration(UiTokens.MOTION_STANDARD),
      displacementEnabled ? RootShellPolicy.PAGE_ENTER_DISTANCE * normalizedDirection : 0,
      displacementEnabled ? -RootShellPolicy.PAGE_EXIT_DISTANCE * normalizedDirection : 0,
      MotionPolicy.blur(RootShellPolicy.DOCK_BLUR),
      MotionPolicy.blur(RootShellPolicy.SELECTION_BLUR),
    );
  }

  static dockHeight(): number {
    return UiTokens.DOCK_HEIGHT;
  }

  static dockHorizontalMargin(): number {
    return RootShellPolicy.DOCK_HORIZONTAL_MARGIN;
  }

  static dockBottomMargin(): number {
    return RootShellPolicy.DOCK_BOTTOM_MARGIN;
  }

  static contentBottomInset(): number {
    return UiTokens.DOCK_HEIGHT + RootShellPolicy.ROOT_CONTENT_GAP;
  }
}

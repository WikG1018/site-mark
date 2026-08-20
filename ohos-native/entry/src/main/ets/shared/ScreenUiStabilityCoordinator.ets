export enum BackAction {
  CONSUME = 0,
  EXIT_SELECTION = 1,
  CLOSE_CONFIRMATION = 2,
  CLOSE_FILTER = 3,
  CLEAR_SEARCH = 4,
  NAVIGATE = 5,
}

export interface BackState {
  busy: boolean;
  selection: boolean;
  confirmation: boolean;
  filter: boolean;
  search: boolean;
}

export class BackCoordinator {
  static next(state: BackState): BackAction {
    if (state.busy) return BackAction.CONSUME;
    if (state.selection) return BackAction.EXIT_SELECTION;
    if (state.confirmation) return BackAction.CLOSE_CONFIRMATION;
    if (state.filter) return BackAction.CLOSE_FILTER;
    if (state.search) return BackAction.CLEAR_SEARCH;
    return BackAction.NAVIGATE;
  }
}

export type BackHandler = () => boolean;

export class BackDispatcher {
  private generation: number = 0;
  private handler: BackHandler | null = null;

  register(handler: BackHandler): number {
    this.generation += 1;
    this.handler = handler;
    return this.generation;
  }

  unregister(token: number): void {
    if (token !== this.generation) return;
    this.handler = null;
  }

  handle(): boolean {
    if (this.handler === null) return false;
    return this.handler();
  }
}

export const RootBackDispatcher: BackDispatcher = new BackDispatcher();

export enum ScreenLoadStatus {
  IDLE = 0,
  LOADING = 1,
  READY = 2,
  MISSING = 3,
  ERROR = 4,
}

export class ScreenLoadCoordinator<T> {
  private generation: number = 0;
  private active: boolean = false;
  private loadStatus: ScreenLoadStatus = ScreenLoadStatus.IDLE;
  private loadedValue: T | null = null;

  activate(): void {
    this.generation += 1;
    this.active = true;
  }

  deactivate(): void {
    this.generation += 1;
    this.active = false;
    this.loadStatus = ScreenLoadStatus.IDLE;
    this.loadedValue = null;
  }

  begin(): number {
    if (!this.active) return -1;
    this.generation += 1;
    this.loadStatus = ScreenLoadStatus.LOADING;
    return this.generation;
  }

  resolve(token: number, value: T | null): boolean {
    if (!this.isCurrent(token)) return false;
    this.loadedValue = value;
    this.loadStatus = value === null ? ScreenLoadStatus.MISSING : ScreenLoadStatus.READY;
    return true;
  }

  reject(token: number): boolean {
    if (!this.isCurrent(token)) return false;
    this.loadedValue = null;
    this.loadStatus = ScreenLoadStatus.ERROR;
    return true;
  }

  isCurrent(token: number): boolean {
    return this.active && token === this.generation;
  }

  status(): ScreenLoadStatus {
    return this.loadStatus;
  }

  value(): T | null {
    return this.loadedValue;
  }

  isActive(): boolean {
    return this.active;
  }
}

import { CaptureFilter } from '../domain/Models';
import { ProjectLifecycleStatus } from '../domain/StateMachine';

export function clampFirstVisibleIndex(index: number, itemCount: number): number {
  if (!Number.isFinite(index) || !Number.isFinite(itemCount) || itemCount <= 0) {
    return 0;
  }
  const lastIndex = Math.max(0, Math.floor(itemCount) - 1);
  return Math.min(lastIndex, Math.max(0, Math.floor(index)));
}

export interface ProjectScreenState {
  searchText: string;
  firstVisibleIndex: number;
}

export interface CaptureScreenState {
  filter: CaptureFilter;
  filterOpen: boolean;
  firstVisibleIndex: number;
}

export interface ProjectDetailScreenState {
  filter: CaptureFilter;
  firstVisibleIndex: number;
}

export class ScreenStateStore {
  private readonly projectStates: Map<ProjectLifecycleStatus, ProjectScreenState> = new Map();
  private capturesState: CaptureScreenState = {
    filter: ScreenStateStore.emptyFilter(),
    filterOpen: false,
    firstVisibleIndex: 0,
  };
  private readonly projectDetailStates: Map<string, ProjectDetailScreenState> = new Map();

  saveProject(lifecycle: ProjectLifecycleStatus, state: ProjectScreenState): void {
    this.projectStates.set(lifecycle, ScreenStateStore.copyProjectState(state));
  }

  project(lifecycle: ProjectLifecycleStatus): ProjectScreenState {
    const state = this.projectStates.get(lifecycle);
    if (state === undefined) {
      return { searchText: '', firstVisibleIndex: 0 };
    }
    return ScreenStateStore.copyProjectState(state);
  }

  saveCaptures(state: CaptureScreenState): void {
    this.capturesState = ScreenStateStore.copyCaptureState(state);
  }

  captures(): CaptureScreenState {
    return ScreenStateStore.copyCaptureState(this.capturesState);
  }

  saveProjectDetail(projectId: string, state: ProjectDetailScreenState): void {
    if (this.projectDetailStates.has(projectId)) {
      this.projectDetailStates.delete(projectId);
    }
    this.projectDetailStates.set(projectId, ScreenStateStore.copyProjectDetailState(state));
    if (this.projectDetailStates.size > 8) {
      for (const oldest of this.projectDetailStates.keys()) {
        this.projectDetailStates.delete(oldest);
        break;
      }
    }
  }

  projectDetail(projectId: string): ProjectDetailScreenState {
    const state = this.projectDetailStates.get(projectId);
    if (state === undefined) {
      const empty = ScreenStateStore.emptyFilter();
      empty.projectId = projectId;
      return { filter: empty, firstVisibleIndex: 0 };
    }
    this.projectDetailStates.delete(projectId);
    this.projectDetailStates.set(projectId, state);
    const restored = ScreenStateStore.copyProjectDetailState(state);
    restored.filter.projectId = projectId;
    return restored;
  }

  hasProjectDetail(projectId: string): boolean {
    return this.projectDetailStates.has(projectId);
  }

  projectDetailCount(): number {
    return this.projectDetailStates.size;
  }

  private static emptyFilter(): CaptureFilter {
    return { projectId: '', year: 0, month: 0, day: 0, searchText: '' };
  }

  private static copyFilter(filter: CaptureFilter): CaptureFilter {
    return {
      projectId: filter.projectId,
      year: filter.year,
      month: filter.month,
      day: filter.day,
      searchText: filter.searchText,
    };
  }

  private static copyProjectState(state: ProjectScreenState): ProjectScreenState {
    return { searchText: state.searchText, firstVisibleIndex: state.firstVisibleIndex };
  }

  private static copyCaptureState(state: CaptureScreenState): CaptureScreenState {
    return {
      filter: ScreenStateStore.copyFilter(state.filter),
      filterOpen: state.filterOpen,
      firstVisibleIndex: state.firstVisibleIndex,
    };
  }

  private static copyProjectDetailState(state: ProjectDetailScreenState): ProjectDetailScreenState {
    return {
      filter: ScreenStateStore.copyFilter(state.filter),
      firstVisibleIndex: state.firstVisibleIndex,
    };
  }
}

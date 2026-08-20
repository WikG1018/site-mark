import { AppDatabase } from '../../data/database/AppDatabase';

export class ProjectSaveCreated {
  readonly id: string;

  constructor(id: string) {
    this.id = id;
  }
}

export interface ProjectSaveStore {
  renameProject(id: string, name: string): Promise<void>;
  updateProjectDescription(id: string, description: string): Promise<void>;
  updateProjectWatermark(id: string, position: string, opacity: number,
    accent: number, fontScale: number): Promise<void>;
  createProject(name: string, description: string): Promise<ProjectSaveCreated>;
}

export class AppDatabaseProjectSaveStore implements ProjectSaveStore {
  private readonly database: AppDatabase;

  constructor(database: AppDatabase) {
    this.database = database;
  }

  renameProject(id: string, name: string): Promise<void> {
    return this.database.renameProject(id, name);
  }

  updateProjectDescription(id: string, description: string): Promise<void> {
    return this.database.updateProjectDescription(id, description);
  }

  updateProjectWatermark(id: string, position: string, opacity: number,
    accent: number, fontScale: number): Promise<void> {
    return this.database.updateProjectWatermark(id, position, opacity, accent, fontScale);
  }

  async createProject(name: string, description: string): Promise<ProjectSaveCreated> {
    const project = await this.database.createProject(name, description);
    return new ProjectSaveCreated(project.id);
  }
}

export class ProjectEditorSaveSnapshot {
  readonly editing: boolean;
  readonly projectId: string;
  readonly name: string;
  readonly description: string;

  constructor(editing: boolean, projectId: string, name: string, description: string) {
    this.editing = editing;
    this.projectId = projectId;
    this.name = name;
    this.description = description;
  }
}

export class WatermarkSaveSnapshot {
  readonly projectId: string;
  readonly position: string;
  readonly opacity: number;
  readonly accent: number;
  readonly fontScale: number;

  constructor(projectId: string, position: string, opacity: number, accent: number,
    fontScale: number) {
    this.projectId = projectId;
    this.position = position;
    this.opacity = opacity;
    this.accent = accent;
    this.fontScale = fontScale;
  }
}

export class ProjectEditorSaveExecutor {
  static async persistEditor(store: ProjectSaveStore, snapshot: ProjectEditorSaveSnapshot): Promise<string> {
    if (!snapshot.editing) {
      const created = await store.createProject(snapshot.name, snapshot.description);
      return created.id;
    }
    await store.renameProject(snapshot.projectId, snapshot.name);
    await store.updateProjectDescription(snapshot.projectId, snapshot.description);
    return snapshot.projectId;
  }

  static persistWatermark(store: ProjectSaveStore, snapshot: WatermarkSaveSnapshot): Promise<void> {
    return store.updateProjectWatermark(snapshot.projectId, snapshot.position, snapshot.opacity,
      snapshot.accent, snapshot.fontScale);
  }
}

export class ProjectDetailMutationPolicy {
  static enabled(batchBusy: boolean, projectPresent: boolean): boolean {
    return !batchBusy && projectPresent;
  }
}

export enum ProjectOperationKind {
  NONE = 0,
  BATCH = 1,
  MUTATION = 2,
}

export class ProjectOperationCoordinator {
  private epoch: number = 0;
  private nextToken: number = 0;
  private inFlightToken: number = -1;
  private inFlightEpoch: number = -1;
  private active: boolean = false;
  private kind: ProjectOperationKind = ProjectOperationKind.NONE;

  activate(): void {
    this.epoch += 1;
    this.active = true;
  }

  invalidate(): void {
    this.epoch += 1;
    this.active = false;
  }

  begin(kind: ProjectOperationKind): number | null {
    if (!this.active || kind === ProjectOperationKind.NONE || this.inFlightToken >= 0) return null;
    this.nextToken += 1;
    this.inFlightToken = this.nextToken;
    this.inFlightEpoch = this.epoch;
    this.kind = kind;
    return this.inFlightToken;
  }

  isCurrent(token: number): boolean {
    return this.active && token === this.inFlightToken && this.inFlightEpoch === this.epoch;
  }

  finish(token: number): boolean {
    if (token !== this.inFlightToken) return false;
    const canCommit = this.isCurrent(token);
    this.inFlightToken = -1;
    this.inFlightEpoch = -1;
    this.kind = ProjectOperationKind.NONE;
    return canCommit;
  }

  isBusy(): boolean {
    return this.inFlightToken >= 0;
  }
}

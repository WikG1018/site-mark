import { AppDatabase } from '../../data/database/AppDatabase';

export class ProjectSaveProject {
  readonly id: string;
  readonly description: string;
  readonly watermarkPosition: string;
  readonly watermarkOpacity: number;
  readonly watermarkAccentColorArgb: number;
  readonly watermarkFontScale: number;

  constructor(id: string, description: string, position: string, opacity: number, accent: number,
    fontScale: number) {
    this.id = id;
    this.description = description;
    this.watermarkPosition = position;
    this.watermarkOpacity = opacity;
    this.watermarkAccentColorArgb = accent;
    this.watermarkFontScale = fontScale;
  }
}

export class ProjectSaveCreated {
  readonly id: string;

  constructor(id: string) {
    this.id = id;
  }
}

export interface ProjectSaveStore {
  renameProject(id: string, name: string): Promise<void>;
  projectById(id: string): Promise<ProjectSaveProject | null>;
  updateProject(id: string, description: string, position: string, opacity: number,
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

  async projectById(id: string): Promise<ProjectSaveProject | null> {
    const project = await this.database.projectById(id);
    if (project === null) return null;
    return new ProjectSaveProject(project.id, project.description, project.watermarkPosition,
      project.watermarkOpacity, project.watermarkAccentColorArgb, project.watermarkFontScale);
  }

  updateProject(id: string, description: string, position: string, opacity: number,
    accent: number, fontScale: number): Promise<void> {
    return this.database.updateProject(id, description, position, opacity, accent, fontScale);
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
  readonly description: string;
  readonly position: string;
  readonly opacity: number;
  readonly accent: number;
  readonly fontScale: number;

  constructor(projectId: string, description: string, position: string, opacity: number, accent: number,
    fontScale: number) {
    this.projectId = projectId;
    this.description = description;
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
    const project = await store.projectById(snapshot.projectId);
    if (project !== null) {
      await store.updateProject(snapshot.projectId, snapshot.description, project.watermarkPosition,
        project.watermarkOpacity, project.watermarkAccentColorArgb, project.watermarkFontScale);
    }
    return snapshot.projectId;
  }

  static persistWatermark(store: ProjectSaveStore, snapshot: WatermarkSaveSnapshot): Promise<void> {
    return store.updateProject(snapshot.projectId, snapshot.description, snapshot.position, snapshot.opacity,
      snapshot.accent, snapshot.fontScale);
  }
}

export class ProjectDetailMutationPolicy {
  static enabled(batchBusy: boolean, projectPresent: boolean): boolean {
    return !batchBusy && projectPresent;
  }
}

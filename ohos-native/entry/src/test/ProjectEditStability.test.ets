import { describe, expect, it } from '@ohos/hypium';
import { ProjectDetailMutationPolicy, ProjectEditorSaveExecutor, ProjectEditorSaveSnapshot,
  ProjectSaveCreated, ProjectSaveProject, ProjectSaveStore, WatermarkSaveSnapshot }
  from '../main/ets/feature/projects/ProjectEditStability';

class DeferredVoid {
  readonly promise: Promise<void>;
  private complete: (() => void) | null = null;

  constructor() {
    this.promise = new Promise<void>((resolve: () => void): void => { this.complete = resolve; });
  }

  resolve(): void {
    this.complete?.();
  }
}

class FakeSaveStore implements ProjectSaveStore {
  readonly renameGate: DeferredVoid = new DeferredVoid();
  renamedId: string = '';
  renamedName: string = '';
  loadedId: string = '';
  updatedId: string = '';
  updatedDescription: string = '';
  updatedPosition: string = '';
  updatedOpacity: number = 0;
  updatedAccent: number = 0;
  updatedFontScale: number = 0;

  async renameProject(id: string, name: string): Promise<void> {
    this.renamedId = id;
    this.renamedName = name;
    await this.renameGate.promise;
  }

  projectById(id: string): Promise<ProjectSaveProject | null> {
    this.loadedId = id;
    return Promise.resolve(new ProjectSaveProject(id, 'old', 'bottomLeft', 0.78, 0xFF000000, 1));
  }

  updateProject(id: string, description: string, position: string, opacity: number,
    accent: number, fontScale: number): Promise<void> {
    this.updatedId = id;
    this.updatedDescription = description;
    this.updatedPosition = position;
    this.updatedOpacity = opacity;
    this.updatedAccent = accent;
    this.updatedFontScale = fontScale;
    return Promise.resolve();
  }

  createProject(_name: string, _description: string): Promise<ProjectSaveCreated> {
    return Promise.resolve(new ProjectSaveCreated('created'));
  }
}

export default function projectEditStabilityTest(): void {
  describe('Project edit stability', () => {
    it('keeps the original editor snapshot across an interleaved await', 0, async () => {
      const store = new FakeSaveStore();
      let selectedProjectId = 'project-a';
      let name = 'Project A';
      let description = 'Description A';
      const snapshot = new ProjectEditorSaveSnapshot(true, selectedProjectId, name, description);
      const saving = ProjectEditorSaveExecutor.persistEditor(store, snapshot);

      selectedProjectId = 'project-b';
      name = 'Project B';
      description = 'Description B';
      store.renameGate.resolve();
      const savedId = await saving;

      expect(savedId).assertEqual('project-a');
      expect(store.renamedId).assertEqual('project-a');
      expect(store.renamedName).assertEqual('Project A');
      expect(store.loadedId).assertEqual('project-a');
      expect(store.updatedId).assertEqual('project-a');
      expect(store.updatedDescription).assertEqual('Description A');
    });

    it('persists a complete watermark snapshot instead of live form values', 0, async () => {
      const store = new FakeSaveStore();
      const snapshot = new WatermarkSaveSnapshot('project-a', 'description', 'topRight', 0.55,
        0xFF112233, 1.25);
      await ProjectEditorSaveExecutor.persistWatermark(store, snapshot);

      expect(store.updatedId).assertEqual('project-a');
      expect(store.updatedDescription).assertEqual('description');
      expect(store.updatedPosition).assertEqual('topRight');
      expect(store.updatedOpacity).assertEqual(0.55);
      expect(store.updatedAccent).assertEqual(0xFF112233);
      expect(store.updatedFontScale).assertEqual(1.25);
    });

    it('disables every project mutation while a batch action is running', 0, () => {
      expect(ProjectDetailMutationPolicy.enabled(true, true)).assertFalse();
      expect(ProjectDetailMutationPolicy.enabled(false, false)).assertFalse();
      expect(ProjectDetailMutationPolicy.enabled(false, true)).assertTrue();
    });
  });
}

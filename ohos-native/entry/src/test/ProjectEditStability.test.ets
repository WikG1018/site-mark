import { describe, expect, it } from '@ohos/hypium';
import { ProjectDetailMutationPolicy, ProjectEditorSaveExecutor, ProjectEditorSaveSnapshot,
  ProjectOperationCoordinator, ProjectOperationKind, ProjectSaveCreated, ProjectSaveStore,
  WatermarkSaveSnapshot }
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
  updatedId: string = '';
  updatedDescription: string = '';
  updatedPosition: string = '';
  updatedOpacity: number = 0;
  updatedAccent: number = 0;
  updatedFontScale: number = 0;
  descriptionGate: DeferredVoid | null = null;

  async renameProject(id: string, name: string): Promise<void> {
    this.renamedId = id;
    this.renamedName = name;
    await this.renameGate.promise;
  }

  async updateProjectDescription(id: string, description: string): Promise<void> {
    if (this.descriptionGate !== null) await this.descriptionGate.promise;
    this.updatedId = id;
    this.updatedDescription = description;
  }

  updateProjectWatermark(id: string, position: string, opacity: number,
    accent: number, fontScale: number): Promise<void> {
    this.updatedId = id;
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
      expect(store.updatedId).assertEqual('project-a');
      expect(store.updatedDescription).assertEqual('Description A');
    });

    it('persists a complete watermark snapshot instead of live form values', 0, async () => {
      const store = new FakeSaveStore();
      const snapshot = new WatermarkSaveSnapshot('project-a', 'bottomRight', 0.55, 0xFF112233, 1.25);
      await ProjectEditorSaveExecutor.persistWatermark(store, snapshot);

      expect(store.updatedId).assertEqual('project-a');
      expect(store.updatedDescription).assertEqual('');
      expect(store.updatedPosition).assertEqual('bottomRight');
      expect(store.updatedOpacity).assertEqual(0.55);
      expect(store.updatedAccent).assertEqual(0xFF112233);
      expect(store.updatedFontScale).assertEqual(1.25);
    });

    it('keeps description and watermark changes when their saves finish in reverse order', 0, async () => {
      const store = new FakeSaveStore();
      store.renameGate.resolve();
      store.descriptionGate = new DeferredVoid();
      const editor = ProjectEditorSaveExecutor.persistEditor(store,
        new ProjectEditorSaveSnapshot(true, 'project-a', 'Project A', 'new description'));
      await ProjectEditorSaveExecutor.persistWatermark(store,
        new WatermarkSaveSnapshot('project-a', 'bottomRight', 0.6, 0xFF223344, 1.3));
      store.descriptionGate.resolve();
      await editor;

      expect(store.updatedDescription).assertEqual('new description');
      expect(store.updatedPosition).assertEqual('bottomRight');
      expect(store.updatedOpacity).assertEqual(0.6);
      expect(store.updatedAccent).assertEqual(0xFF223344);
      expect(store.updatedFontScale).assertEqual(1.3);
    });

    it('disables every project mutation while a batch action is running', 0, () => {
      expect(ProjectDetailMutationPolicy.enabled(true, true)).assertFalse();
      expect(ProjectDetailMutationPolicy.enabled(false, false)).assertFalse();
      expect(ProjectDetailMutationPolicy.enabled(false, true)).assertTrue();
    });

    it('rejects batch and mutation operations in both overlap directions', 0, () => {
      const operations = new ProjectOperationCoordinator();
      operations.activate();
      const mutation = operations.begin(ProjectOperationKind.MUTATION);
      expect(mutation === null).assertFalse();
      expect(operations.begin(ProjectOperationKind.BATCH) === null).assertTrue();
      operations.finish(mutation as number);
      const batch = operations.begin(ProjectOperationKind.BATCH);
      expect(batch === null).assertFalse();
      expect(operations.begin(ProjectOperationKind.MUTATION) === null).assertTrue();
      operations.finish(batch as number);
    });

    it('keeps a stale operation locked until its completion after reactivation', 0, () => {
      const operations = new ProjectOperationCoordinator();
      operations.activate();
      const mutation = operations.begin(ProjectOperationKind.MUTATION);
      expect(mutation === null).assertFalse();
      operations.invalidate();
      operations.activate();
      expect(operations.begin(ProjectOperationKind.BATCH) === null).assertTrue();
      expect(operations.finish(mutation as number)).assertFalse();
      expect(operations.begin(ProjectOperationKind.BATCH) === null).assertFalse();
    });
  });
}

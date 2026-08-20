import { AppRuntime } from '../../app/AppRuntime';
import { Routes } from '../../app/Routes';
import { CaptureFilter, CapturePage, CapturePageCursor, CaptureRecord, ProjectRecord,
  ProjectSummary } from '../../domain/Models';
import { ProjectLifecycleStatus } from '../../domain/StateMachine';
import { CaptureCard } from '../records/RecordComponents';
import { AppTopBar, EmptyPanel, InlineErrorPanel, ListSkeleton, SectionHeader } from '../../shared/AppComponents';
import { formatDateTime, lifecycleLabel } from '../../shared/Formatters';
import { UiTokens } from '../../shared/UiTokens';
import { ProjectBackupService } from '../backup/BackupService';
import { tr } from '../../shared/AppText';
import { LazyListDataSource } from '../../shared/LazyListDataSource';
import { clampFirstVisibleIndex } from '../../shared/ScreenStateStore';
import { ProjectCard } from './ProjectComponents';
import { CapturePageLoader, CapturePagedController } from '../records/CapturePagedController';

class RuntimeCapturePageLoader implements CapturePageLoader {
  load(filter: CaptureFilter, cursor: CapturePageCursor | null, pageSize: number): Promise<CapturePage> {
    return AppRuntime.require().database.listCaptures(filter, cursor, pageSize);
  }
}

@Component
export struct ProjectListView {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private lifecycle: ProjectLifecycleStatus = ProjectLifecycleStatus.ACTIVE;
  @State private searchText: string = '';
  @State private loading: boolean = true;
  @State private message: string = '';
  @State private projectCount: number = 0;
  private readonly projectSource: LazyListDataSource<ProjectSummary> =
    new LazyListDataSource<ProjectSummary>((item: ProjectSummary): string => item.project.id);
  private readonly projectScroller: Scroller = new Scroller();
  private searchTimer: number = -1;
  private restoreTimer: number = -1;
  private loadGeneration: number = 0;
  private savedFirstVisibleIndex: number = 0;
  private restorePending: boolean = true;
  private visible: boolean = false;
  private readonly refreshListener: () => void = (): void => { this.load(); };
  private readonly memoryListener: (level: number) => void = (_level: number): void => {
    this.cancelRestoreTimer();
  };

  aboutToAppear(): void {
    const runtime = AppRuntime.require();
    this.visible = true;
    const restored = runtime.screenState.project(this.lifecycle);
    this.searchText = restored.searchText;
    this.savedFirstVisibleIndex = restored.firstVisibleIndex;
    this.restorePending = true;
    runtime.subscribe(this.refreshListener);
    runtime.uiMemory.register(this.memoryListener);
    this.load();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.saveProjectState();
    this.cancelTimers();
    this.loadGeneration += 1;
    AppRuntime.current?.unsubscribe(this.refreshListener);
    AppRuntime.current?.uiMemory.unregister(this.memoryListener);
  }

  aboutToBeDeleted(): void {
    this.visible = false;
    this.saveProjectState();
    this.cancelTimers();
    this.loadGeneration += 1;
    AppRuntime.current?.unsubscribe(this.refreshListener);
    AppRuntime.current?.uiMemory.unregister(this.memoryListener);
  }

  private cancelRestoreTimer(): void {
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
  }

  private cancelTimers(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.cancelRestoreTimer();
  }

  private saveProjectState(): void {
    const runtime = AppRuntime.current;
    if (runtime === null) {
      return;
    }
    runtime.screenState.saveProject(this.lifecycle, {
      searchText: this.searchText,
      firstVisibleIndex: this.savedFirstVisibleIndex,
    });
  }

  private scheduleRestore(generation: number): void {
    if (!this.restorePending || this.projectCount === 0) {
      return;
    }
    this.cancelRestoreTimer();
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (!this.visible || generation !== this.loadGeneration || !this.restorePending || this.projectCount === 0) {
        return;
      }
      const index = clampFirstVisibleIndex(this.savedFirstVisibleIndex, this.projectCount);
      this.savedFirstVisibleIndex = index;
      this.saveProjectState();
      this.projectScroller.scrollToIndex(index, false, ScrollAlign.START);
      this.restorePending = false;
    }, 0);
  }

  private async load(): Promise<void> {
    const generation = ++this.loadGeneration;
    this.loading = true;
    try {
      const projects = await AppRuntime.require().database.listProjectSummaries(this.lifecycle, this.searchText);
      if (!this.visible || generation !== this.loadGeneration) return;
      this.projectSource.replace(projects);
      this.projectCount = projects.length;
      this.message = '';
      this.scheduleRestore(generation);
    } catch (_) {
      if (this.visible && generation === this.loadGeneration) {
        this.message = tr('项目加载失败，请稍后重试', 'Projects could not be loaded. Try again.');
      }
    } finally {
      if (this.visible && generation === this.loadGeneration) {
        this.loading = false;
      }
    }
  }

  private scheduleSearch(): void {
    if (this.searchTimer >= 0) clearTimeout(this.searchTimer);
    this.savedFirstVisibleIndex = 0;
    this.restorePending = true;
    this.saveProjectState();
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.load();
    }, 250);
  }

  private openProject(item: ProjectSummary): void {
    AppRuntime.require().selectedProjectId = item.project.id;
    this.pathStack.pushPathByName(Routes.PROJECT_DETAIL, null);
  }

  private createProject(): void {
    AppRuntime.require().selectedProjectId = '';
    this.pathStack.pushPathByName(Routes.PROJECT_EDITOR, null);
  }

  private switchLifecycle(value: ProjectLifecycleStatus): void {
    if (value === this.lifecycle) {
      return;
    }
    this.saveProjectState();
    this.lifecycle = value;
    const restored = AppRuntime.require().screenState.project(value);
    this.searchText = restored.searchText;
    this.savedFirstVisibleIndex = restored.firstVisibleIndex;
    this.restorePending = true;
    this.load();
  }

  @Builder
  private statusChip(label: string, value: ProjectLifecycleStatus) {
    Button(label)
      .height(38)
      .layoutWeight(1)
      .fontSize(14)
      .fontWeight(this.lifecycle === value ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.lifecycle === value ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
      .backgroundColor(this.lifecycle === value ? UiTokens.PRIMARY_CONTAINER : Color.Transparent)
      .borderRadius(19)
      .onClick((): void => {
        this.switchLifecycle(value);
      })
  }

  build() {
    Column() {
      AppTopBar({ title: tr('项目', 'Projects'), subtitle: tr('工程现场按项目归档',
        'Organize site records by project'), actionLabel: tr('＋ 新建', '＋ New'),
        onAction: (): void => this.createProject() })
      Column({ space: 12 }) {
        TextInput({ text: this.searchText, placeholder: tr('搜索项目名称', 'Search project names') })
          .height(44)
          .fontSize(15)
          .backgroundColor(UiTokens.GLASS_STRONG)
          .borderRadius(22)
          .onChange((value: string): void => {
            this.searchText = value;
            this.scheduleSearch();
          })
        Row({ space: 6 }) {
          this.statusChip(tr('进行中', 'Active'), ProjectLifecycleStatus.ACTIVE)
          this.statusChip(tr('已完成', 'Completed'), ProjectLifecycleStatus.COMPLETED)
          this.statusChip(tr('已归档', 'Archived'), ProjectLifecycleStatus.ARCHIVED)
        }
        .padding(4)
        .width('100%')
        .backgroundColor(UiTokens.CONTROL)
        .borderRadius(24)
      }
      .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, bottom: 8 })
      .width('100%')
      if (this.message.length > 0 && this.projectCount > 0) {
        Column() {
          InlineErrorPanel({ message: this.message, retryLabel: tr('重试', 'Retry'),
            onRetry: (): void => { this.load(); } })
        }
        .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, bottom: 6 })
        .width('100%')
      }
      if (this.loading && this.projectCount === 0) {
        ListSkeleton({ rows: 3 })
      } else if (this.message.length > 0 && this.projectCount === 0) {
        Column() {
          InlineErrorPanel({ message: this.message, retryLabel: tr('重试', 'Retry'),
            onRetry: (): void => { this.load(); } })
        }
        .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 12 })
        .width('100%')
      } else if (!this.loading && this.projectCount === 0) {
        EmptyPanel({ icon: '▦',
            title: this.searchText.length > 0 ? tr('没有匹配的项目', 'No matching projects') :
              tr('还没有项目', 'No projects yet'),
          message: this.lifecycle === ProjectLifecycleStatus.ACTIVE ?
              tr('先创建工程项目，再开始现场拍摄记录。',
                'Create an engineering project before recording the site.') :
              tr('此状态下暂时没有项目。', 'There are no projects in this status.'),
            actionLabel: this.lifecycle === ProjectLifecycleStatus.ACTIVE ? tr('创建项目', 'Create project') : '',
          onAction: (): void => this.createProject() })
      } else {
        List({ space: 12, scroller: this.projectScroller }) {
          LazyForEach(this.projectSource, (item: ProjectSummary) => {
            ListItem() {
              ProjectCard({ summary: item, onOpen: (): void => this.openProject(item) })
            }
          }, (item: ProjectSummary): string => item.project.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 6, bottom: 112 })
        .cachedCount(4)
        .edgeEffect(EdgeEffect.Spring)
        .onScrollIndex((start: number, _end: number): void => {
          if (this.restorePending) {
            return;
          }
          this.savedFirstVisibleIndex = Math.max(0, start);
          this.saveProjectState();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTokens.BACKGROUND)
  }
}

@Component
export struct ProjectEditorScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private name: string = '';
  @State private description: string = '';
  @State private saving: boolean = false;
  @State private message: string = '';
  @State private editing: boolean = false;

  aboutToAppear(): void {
    const id = AppRuntime.require().selectedProjectId;
    this.editing = id.length > 0;
    if (this.editing) {
      AppRuntime.require().database.projectById(id).then((project: ProjectRecord | null): void => {
        if (project !== null) {
          this.name = project.name;
          this.description = project.description;
        }
      });
    }
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    if (this.name.trim().length === 0) {
      this.message = tr('请输入项目名称', 'Enter a project name');
      return;
    }
    this.saving = true;
    try {
      const runtime = AppRuntime.require();
      if (this.editing) {
        await runtime.database.renameProject(runtime.selectedProjectId, this.name);
        const project = await runtime.database.projectById(runtime.selectedProjectId);
        if (project !== null) {
          await runtime.database.updateProject(project.id, this.description, project.watermarkPosition,
            project.watermarkOpacity, project.watermarkAccentColorArgb, project.watermarkFontScale);
        }
      } else {
        const created = await runtime.database.createProject(this.name, this.description);
        runtime.selectedProjectId = created.id;
      }
      runtime.notifyDataChanged();
      this.pathStack.pop();
    } catch (error) {
      const text = (error as Error).message;
      this.message = text.includes('conflict') ? tr('已存在同名项目或文件名冲突',
        'A project with the same name or file name already exists') :
        tr('项目保存失败，请稍后重试', 'The project could not be saved. Try again.');
    } finally {
      this.saving = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: this.editing ? tr('编辑项目', 'Edit project') : tr('新建项目', 'New project'),
          showBack: true, onBack: (): void => { this.pathStack.pop(); },
          actionLabel: this.saving ? tr('保存中', 'Saving') : tr('保存', 'Save'),
          onAction: (): void => { this.save(); } })
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 8 }) {
            Text(tr('项目名称', 'Project name')).fontSize(14).fontWeight(FontWeight.Medium).width('100%')
            TextInput({ text: this.name, placeholder: tr('例如：云湖之城', 'For example: Riverside Tower') })
                .height(52)
                .fontSize(16)
                .backgroundColor(UiTokens.GLASS_STRONG)
                .borderRadius(18)
                .onChange((value: string): void => { this.name = value; this.message = ''; })
            }.alignItems(HorizontalAlign.Start).width('100%')
            Column({ space: 8 }) {
            Text(tr('项目说明（选填）', 'Project description (optional)')).fontSize(14)
              .fontWeight(FontWeight.Medium).width('100%')
            TextArea({ text: this.description, placeholder: tr('补充项目位置、合同或现场说明',
              'Add the location, contract, or site notes') })
                .height(120)
                .fontSize(15)
                .backgroundColor(UiTokens.GLASS_STRONG)
                .borderRadius(18)
                .onChange((value: string): void => { this.description = value; })
            }.alignItems(HorizontalAlign.Start).width('100%')
            if (this.message.length > 0) {
              Text(this.message).fontSize(14).fontColor(UiTokens.DANGER).width('100%')
            }
            Text(tr('项目名称必须唯一。重命名只影响以后新拍照片，历史编号和文件名不会改变。',
              'Project names must be unique. Renaming only affects future photos; existing numbers and file names stay unchanged.'))
              .fontSize(13)
              .fontColor(UiTokens.TEXT_SECONDARY)
              .lineHeight(20)
              .padding(16)
              .width('100%')
              .backgroundColor(UiTokens.GLASS)
              .borderRadius(18)
          }
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 12, bottom: 40 })
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Start)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(UiTokens.BACKGROUND)
    }
    .hideTitleBar(true)
  }
}

@Component
export struct ProjectDetailScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private project: ProjectRecord | null = null;
  @State private projectLoading: boolean = true;
  @State private controllerRevision: number = 0;
  @State private confirmDelete: boolean = false;
  @State private message: string = '';
  @State private selectionMode: boolean = false;
  @State private selectedIds: string[] = [];
  @State private allSelected: boolean = false;
  @State private batchBusy: boolean = false;
  @State private confirmBatchDelete: boolean = false;
  @State private searchText: string = '';
  @State private filterOpen: boolean = false;
  @State private yearText: string = '';
  @State private monthText: string = '';
  @State private dayText: string = '';
  private readonly controller: CapturePagedController = new CapturePagedController(new RuntimeCapturePageLoader(),
    (): void => { this.controllerRevision += 1; });
  private readonly detailScroller: Scroller = new Scroller();
  private searchTimer: number = -1;
  private restoreTimer: number = -1;
  private projectGeneration: number = 0;
  private contentGeneration: number = 0;
  private savedFirstVisibleIndex: number = 0;
  private restorePending: boolean = true;
  private visible: boolean = false;
  private projectId: string = '';
  private readonly refreshListener: () => void = (): void => { this.refreshContent(); };
  private readonly memoryListener: (level: number) => void = (_level: number): void => {
    this.cancelRestoreTimer();
    this.restorePending = true;
  };

  aboutToAppear(): void {
    const runtime = AppRuntime.require();
    this.visible = true;
    this.projectId = runtime.selectedProjectId;
    const restored = runtime.screenState.projectDetail(this.projectId);
    this.searchText = restored.filter.searchText;
    this.yearText = restored.filter.year > 0 ? restored.filter.year.toString() : '';
    this.monthText = restored.filter.month > 0 ? restored.filter.month.toString() : '';
    this.dayText = restored.filter.day > 0 ? restored.filter.day.toString() : '';
    this.savedFirstVisibleIndex = restored.firstVisibleIndex;
    this.restorePending = true;
    runtime.subscribe(this.refreshListener);
    runtime.uiMemory.register(this.memoryListener);
    this.refreshContent();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.saveDetailState();
    this.cancelTimers();
    this.projectGeneration += 1;
    this.contentGeneration += 1;
    this.controller.invalidate();
    AppRuntime.current?.unsubscribe(this.refreshListener);
    AppRuntime.current?.uiMemory.unregister(this.memoryListener);
  }

  aboutToBeDeleted(): void {
    this.visible = false;
    this.saveDetailState();
    this.cancelTimers();
    this.projectGeneration += 1;
    this.contentGeneration += 1;
    this.controller.invalidate();
    AppRuntime.current?.unsubscribe(this.refreshListener);
    AppRuntime.current?.uiMemory.unregister(this.memoryListener);
  }

  private currentFilter(): CaptureFilter {
    return { projectId: this.projectId,
      year: Number.parseInt(this.yearText) || 0,
      month: Number.parseInt(this.monthText) || 0,
      day: Number.parseInt(this.dayText) || 0,
      searchText: this.searchText };
  }

  private captureCount(): number {
    return this.controllerRevision >= 0 ? this.controller.data.totalCount() : 0;
  }

  private firstCaptureDate(): string {
    if (this.captureCount() === 0) {
      return '';
    }
    return formatDateTime(this.controller.data.getData(0).capturedAt).substring(0, 10);
  }

  private detailItemCount(): number {
    let count = 5;
    if (this.confirmDelete) count += 1;
    if (this.message.length > 0) count += 1;
    if (this.filterOpen) count += 1;
    const captures = this.captureCount();
    count += captures > 0 ? captures : 1;
    if (captures > 0 && (this.controller.loadingInitial || this.controller.loadingMore)) count += 1;
    if (captures > 0 && this.controller.failed) count += 1;
    return count;
  }

  private cancelRestoreTimer(): void {
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
  }

  private cancelTimers(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.cancelRestoreTimer();
  }

  private saveDetailState(): void {
    const runtime = AppRuntime.current;
    if (runtime === null || this.projectId.length === 0) {
      return;
    }
    runtime.screenState.saveProjectDetail(this.projectId, {
      filter: this.currentFilter(),
      firstVisibleIndex: this.savedFirstVisibleIndex,
    });
  }

  private markFilterChanged(): void {
    this.savedFirstVisibleIndex = 0;
    this.restorePending = true;
    this.saveDetailState();
  }

  private scheduleSearch(): void {
    if (this.searchTimer >= 0) clearTimeout(this.searchTimer);
    this.markFilterChanged();
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.resetCaptures();
    }, 250);
  }

  private refreshContent(): void {
    this.loadProject();
    this.resetCaptures();
  }

  private async loadProject(): Promise<void> {
    const generation = ++this.projectGeneration;
    if (this.project === null) {
      this.projectLoading = true;
    }
    try {
      const project = await AppRuntime.require().database.projectById(this.projectId);
      if (!this.visible || generation !== this.projectGeneration) {
        return;
      }
      this.project = project;
      if (project !== null && !this.controller.loadingInitial && !this.controller.failed) {
        this.scheduleDetailRestore(this.contentGeneration);
      }
    } catch (_) {
    } finally {
      if (this.visible && generation === this.projectGeneration) {
        this.projectLoading = false;
      }
    }
  }

  private async resetCaptures(): Promise<void> {
    const generation = ++this.contentGeneration;
    await this.controller.reset(this.currentFilter());
    if (!this.visible || generation !== this.contentGeneration || this.controller.failed || this.project === null) {
      return;
    }
    this.scheduleDetailRestore(generation);
  }

  private async retryCaptures(): Promise<void> {
    const generation = ++this.contentGeneration;
    await this.controller.retry();
    if (!this.visible || generation !== this.contentGeneration || this.controller.failed || this.project === null) {
      return;
    }
    this.scheduleDetailRestore(generation);
  }

  private scheduleDetailRestore(generation: number): void {
    if (!this.restorePending || this.captureCount() === 0) {
      return;
    }
    this.cancelRestoreTimer();
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (!this.visible || generation !== this.contentGeneration || !this.restorePending ||
        this.captureCount() === 0) {
        return;
      }
      const index = clampFirstVisibleIndex(this.savedFirstVisibleIndex, this.detailItemCount());
      this.savedFirstVisibleIndex = index;
      this.saveDetailState();
      this.detailScroller.scrollToIndex(index, false, ScrollAlign.START);
      this.restorePending = false;
    }, 0);
  }

  private openCapture(capture: CaptureRecord): void {
    AppRuntime.require().selectedCaptureId = capture.id;
    this.pathStack.pushPathByName(Routes.CAPTURE_DETAIL, null);
  }

  private setSelectionMode(enabled: boolean): void {
    this.selectionMode = enabled;
    if (!enabled) {
      this.selectedIds = [];
      this.allSelected = false;
      this.confirmBatchDelete = false;
    }
  }

  private toggleCapture(captureId: string): void {
    const index = this.selectedIds.indexOf(captureId);
    if (index >= 0) {
      const next = this.selectedIds.slice();
      next.splice(index, 1);
      this.selectedIds = next;
    } else {
      this.selectedIds = this.selectedIds.concat([captureId]);
    }
    this.allSelected = false;
    this.confirmBatchDelete = false;
  }

  private async toggleAll(): Promise<void> {
    if (this.batchBusy || this.project === null) return;
    if (this.allSelected) {
      this.selectedIds = [];
      this.allSelected = false;
      return;
    }
    this.batchBusy = true;
    try {
      this.selectedIds = await AppRuntime.require().database.captureIds(this.currentFilter());
      this.allSelected = this.selectedIds.length > 0;
    } catch (_) {
      this.message = tr('无法全选项目记录，请重试', 'Could not select every project record. Try again.');
    } finally {
      this.batchBusy = false;
    }
  }

  private async batchExport(): Promise<void> {
    if (this.selectedIds.length === 0) {
      this.message = tr('请先选择照片', 'Select photos first');
      return;
    }
    try {
      const service = new ProjectBackupService(AppRuntime.require());
      const result = await service.exportSelection(this.selectedIds, false);
      const saved = await service.saveAs(result);
      this.message = saved ? tr('所选照片已导出到你选择的位置',
        'Selected photos were exported to your chosen location') :
        tr('已取消保存导出文件', 'Export save was cancelled');
    } catch (_) {
      this.message = tr('所选照片暂时无法导出，请检查记录状态和存储空间',
        'Selected photos could not be exported. Check their status and available storage.');
    }
  }

  private async runBatch(action: (id: string) => Promise<void>, success: string): Promise<void> {
    if (this.batchBusy) return;
    const ids = this.selectedIds.slice();
    if (ids.length === 0) {
      this.message = tr('请先选择照片', 'Select photos first');
      return;
    }
    this.batchBusy = true;
    try {
      let succeeded = 0;
      for (const id of ids) {
        try {
          await action(id);
          succeeded += 1;
        } catch (_) {
        }
      }
      this.message = succeeded === ids.length ? success :
      tr(`已完成 ${succeeded}/${ids.length} 项`, `Completed ${succeeded}/${ids.length}`);
      this.setSelectionMode(false);
      await this.resetCaptures();
    } finally {
      this.batchBusy = false;
    }
  }

  private async batchDelete(): Promise<void> {
    if (!this.confirmBatchDelete) {
      this.confirmBatchDelete = true;
      this.message = tr(`再次点击“确认删除”将永久删除已选 ${this.selectedIds.length} 条记录`,
        `Tap “Confirm delete” again to permanently delete ${this.selectedIds.length} selected records`);
      return;
    }
    await this.runBatch((id: string): Promise<void> => AppRuntime.require().deleteCapture(id),
      tr('所选记录已删除', 'Selected records deleted'));
  }

  @Builder
  private batchBar() {
    Column({ space: 8 }) {
      Text(tr(`已选 ${this.selectedIds.length} 张`, `${this.selectedIds.length} selected`))
        .fontSize(13).fontWeight(FontWeight.Bold)
      Row({ space: 6 }) {
        Button(tr('导出所选', 'Export')).layoutWeight(1).height(42).fontSize(11)
          .backgroundColor(Color.Transparent).fontColor(UiTokens.TEXT).enabled(!this.batchBusy)
          .onClick((): void => { this.batchExport(); })
        Button(tr('再次保存', 'Save')).layoutWeight(1).height(42).fontSize(11)
          .backgroundColor(Color.Transparent).fontColor(UiTokens.TEXT).enabled(!this.batchBusy)
          .onClick((): void => { this.runBatch((id: string): Promise<void> =>
            AppRuntime.require().republishCapture(id), tr('已再次保存到相册', 'Saved to the gallery')); })
        Button(tr('清理原图', 'Clear originals')).layoutWeight(1).height(42).fontSize(11)
          .backgroundColor(Color.Transparent).fontColor(UiTokens.TEXT).enabled(!this.batchBusy)
          .onClick((): void => { this.runBatch((id: string): Promise<void> =>
            AppRuntime.require().clearOriginal(id), tr('原图清理已完成', 'Original cleanup completed')); })
        Button(this.confirmBatchDelete ? tr('确认删除', 'Confirm delete') : tr('删除所选', 'Delete'))
          .layoutWeight(1).height(42).fontSize(11)
          .fontColor(UiTokens.DANGER).backgroundColor(Color.Transparent).enabled(!this.batchBusy)
          .onClick((): void => { this.batchDelete(); })
      }.width('100%')
    }
    .padding({ left: 12, right: 12, top: 9, bottom: 10 })
    .margin({ left: 16, right: 16, bottom: 12 })
    .width('100%').backgroundColor(UiTokens.GLASS_STRONG).backdropBlur(24)
    .border({ width: 1, color: UiTokens.OUTLINE }).borderRadius(26)
    .shadow({ radius: 18, color: '#28000000', offsetY: 6 })
  }

  @Builder
  private recordFilterPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.yearText, placeholder: tr('年', 'Year') }).layoutWeight(1).height(42)
          .type(InputType.Number)
          .onChange((value: string): void => { this.yearText = value; this.markFilterChanged(); })
        TextInput({ text: this.monthText, placeholder: tr('月', 'Month') }).layoutWeight(1).height(42)
          .type(InputType.Number)
          .onChange((value: string): void => { this.monthText = value; this.markFilterChanged(); })
        TextInput({ text: this.dayText, placeholder: tr('日', 'Day') }).layoutWeight(1).height(42)
          .type(InputType.Number)
          .onChange((value: string): void => { this.dayText = value; this.markFilterChanged(); })
      }.width('100%')
      Row({ space: 8 }) {
          Button(tr('清除日期', 'Clear date')).layoutWeight(1).height(38)
            .backgroundColor(UiTokens.CONTROL).fontColor(UiTokens.TEXT)
          .onClick((): void => {
            this.yearText = ''; this.monthText = ''; this.dayText = '';
            this.markFilterChanged();
            this.resetCaptures();
          })
          Button(tr('应用筛选', 'Apply filters')).layoutWeight(1).height(38)
            .backgroundColor(UiTokens.PRIMARY).fontColor(Color.White)
          .onClick((): void => { this.filterOpen = false; this.markFilterChanged(); this.resetCaptures(); })
      }.width('100%')
    }
    .padding(14).margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
    .backgroundColor(UiTokens.GLASS_STRONG).borderRadius(20).width(`calc(100% - ${UiTokens.PAGE_PADDING * 2}vp)`)
  }

  private async setLifecycle(target: ProjectLifecycleStatus): Promise<void> {
    if (this.project === null) {
      return;
    }
    try {
      await AppRuntime.require().database.setProjectLifecycle(this.project.id, target, true);
      AppRuntime.require().notifyDataChanged();
      await this.loadProject();
      await this.resetCaptures();
    } catch (_) {
      this.message = tr('有照片仍在处理中，暂时不能更改项目状态',
        'Project status cannot change while photos are processing');
    }
  }

  private async togglePinned(): Promise<void> {
    if (this.project === null) {
      return;
    }
    await AppRuntime.require().database.setProjectPinned(this.project.id, !this.project.isPinned);
    AppRuntime.require().notifyDataChanged();
    await this.loadProject();
    await this.resetCaptures();
  }

  private async deleteProject(): Promise<void> {
    if (this.project === null) {
      return;
    }
    try {
      await AppRuntime.require().deleteProject(this.project.id);
      this.pathStack.pop();
    } catch (_) {
      this.message = tr('有照片仍在处理中，项目暂时不能删除',
        'The project cannot be deleted while photos are processing');
    }
  }

  @Builder
  private projectSummary() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text('▦').fontSize(34).fontColor(UiTokens.PRIMARY)
        Column({ space: 4 }) {
          Text(this.project!.name).fontSize(22).fontWeight(FontWeight.Bold).fontColor(UiTokens.TEXT)
            .maxLines(2).width('100%')
          Text(lifecycleLabel(this.project!.lifecycleStatus)).fontSize(13).fontColor(UiTokens.PRIMARY)
            .width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      if (this.project!.description.length > 0) {
        Text(this.project!.description).fontSize(14).fontColor(UiTokens.TEXT_SECONDARY)
          .lineHeight(21).width('100%')
      }
      Row({ space: 8 }) {
        Button(this.project!.isPinned ? tr('取消置顶', 'Unpin') : tr('置顶', 'Pin'))
          .height(38).layoutWeight(1).fontSize(13).backgroundColor('#E3EEE8')
          .fontColor(UiTokens.PRIMARY).borderRadius(19).onClick((): void => { this.togglePinned(); })
        Button(tr('此项目水印设置', 'Project watermark settings'))
          .height(38).layoutWeight(2).fontSize(13).backgroundColor('#E3EEE8')
          .fontColor(UiTokens.PRIMARY).borderRadius(19)
          .onClick((): void => { this.pathStack.pushPathByName(Routes.PROJECT_SETTINGS, null); })
      }.width('100%')
    }
    .padding(18)
    .margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 8 })
    .width(`calc(100% - ${UiTokens.PAGE_PADDING * 2}vp)`)
    .backgroundColor(UiTokens.PRIMARY_CONTAINER)
    .borderRadius(UiTokens.CARD_RADIUS)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          AppTopBar({ title: this.selectionMode ? tr(`已选 ${this.selectedIds.length} 张`,
            `${this.selectedIds.length} selected`) : (this.project?.name ?? tr('项目', 'Project')), showBack: true,
            onBack: (): void => { if (this.selectionMode) this.setSelectionMode(false); else this.pathStack.pop(); },
            actionLabel: this.selectionMode ? tr('完成', 'Done') : tr('编辑', 'Edit'),
            onAction: (): void => { if (this.selectionMode) this.setSelectionMode(false);
              else this.pathStack.pushPathByName(Routes.PROJECT_EDITOR, null); } })
          if (this.project !== null) {
            List({ space: 10, scroller: this.detailScroller }) {
              ListItem() { this.projectSummary() }
              ListItem() { SectionHeader({ title: tr('项目操作', 'Project actions') }) }
              ListItem() {
                Row({ space: 8 }) {
                  if (this.project!.lifecycleStatus !== ProjectLifecycleStatus.ACTIVE) {
                    Button(tr('恢复进行中', 'Reopen')).layoutWeight(1).height(38).fontSize(12)
                      .fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.ACCENT_SURFACE)
                      .onClick((): void => { this.setLifecycle(ProjectLifecycleStatus.ACTIVE); })
                  } else {
                    Button(tr('标记完成', 'Mark completed')).layoutWeight(1).height(38).fontSize(12)
                      .fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.ACCENT_SURFACE)
                      .onClick((): void => { this.setLifecycle(ProjectLifecycleStatus.COMPLETED); })
                  }
                  if (this.project!.lifecycleStatus !== ProjectLifecycleStatus.ARCHIVED) {
                    Button(tr('归档', 'Archive')).layoutWeight(1).height(38).fontSize(12)
                      .fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.ACCENT_SURFACE)
                      .onClick((): void => { this.setLifecycle(ProjectLifecycleStatus.ARCHIVED); })
                  }
                  Button(tr('删除项目', 'Delete project')).layoutWeight(1).height(38).fontSize(12)
                    .fontColor(UiTokens.DANGER).backgroundColor(UiTokens.DANGER_CONTAINER)
                    .onClick((): void => { this.confirmDelete = !this.confirmDelete; })
                }
                .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
                .width('100%')
              }
              if (this.confirmDelete) {
                ListItem() {
                  Column({ space: 10 }) {
                    Text(tr('删除后，应用内项目、记录和私有文件无法恢复；系统相册照片与已保存备份会保留。',
                      'The in-app project, records, and private files cannot be recovered. Gallery photos and saved backups remain.'))
                      .fontSize(13).fontColor(UiTokens.DANGER).lineHeight(19).width('100%')
                    Row({ space: 8 }) {
                      Button(tr('取消', 'Cancel')).layoutWeight(1).height(38)
                        .onClick((): void => { this.confirmDelete = false; })
                      Button(tr('确认删除', 'Confirm delete')).layoutWeight(1).height(38)
                        .backgroundColor(UiTokens.DANGER)
                        .fontColor(Color.White).onClick((): void => { this.deleteProject(); })
                    }.width('100%')
                  }
                  .padding(14).margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
                  .backgroundColor(UiTokens.DELETE_PANEL).borderRadius(16)
                }
              }
              if (this.message.length > 0) {
                ListItem() {
                  Text(this.message).fontSize(13).fontColor(UiTokens.PRIMARY)
                    .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
                    .width('100%')
                }
              }
              ListItem() {
                Column({ space: 8 }) {
                  TextInput({ text: this.searchText, placeholder: tr('搜索部位、内容、拍摄人或编号',
                    'Search location, work, photographer, or number') })
                    .height(44).fontSize(14).backgroundColor(UiTokens.GLASS_STRONG).borderRadius(22)
                    .onChange((value: string): void => { this.searchText = value; this.scheduleSearch(); })
                  Row({ space: 8 }) {
                    Button(this.filterOpen ? tr('收起筛选', 'Hide filters') : tr('筛选', 'Filter'))
                      .height(38).fontSize(13).fontColor(UiTokens.PRIMARY)
                      .backgroundColor(UiTokens.ACCENT_SURFACE)
                      .onClick((): void => { this.filterOpen = !this.filterOpen; })
                    Blank()
                    if (this.captureCount() > 0) {
                      Text(this.firstCaptureDate())
                        .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY)
                    }
                  }.width('100%')
                }
                .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
                .width('100%')
              }
              if (this.filterOpen) {
                ListItem() { this.recordFilterPanel() }
              }
              ListItem() {
                Row({ space: 8 }) {
                  Text(tr('拍摄记录', 'Capture records')).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1)
                  Text(tr(`${this.captureCount()}${this.controller.hasMore ? '+' : ''} 条`,
                    `${this.captureCount()}${this.controller.hasMore ? '+' : ''}`))
                    .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY)
                  if (this.captureCount() > 0) {
                    Button(this.selectionMode ? (this.allSelected ? tr('取消全选', 'Deselect all') :
                      tr('全选', 'Select all')) : tr('选择', 'Select'))
                      .height(36).fontSize(12)
                      .fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.ACCENT_SURFACE)
                      .enabled(!this.batchBusy)
                      .onClick((): void => { if (this.selectionMode) this.toggleAll();
                        else this.setSelectionMode(true); })
                  }
                }
                .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 6 })
                .width('100%')
              }
              if (this.controller.loadingInitial && this.captureCount() === 0) {
                ListItem() { ListSkeleton({ rows: 2 }) }
              } else if (this.controller.failed && this.captureCount() === 0) {
                ListItem() {
                  Column() {
                    InlineErrorPanel({
                      message: tr('项目记录加载失败，请重试', 'Project records could not be loaded. Try again.'),
                      retryLabel: tr('重试', 'Retry'), onRetry: (): void => { this.retryCaptures(); },
                    })
                  }
                  .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
                  .width('100%')
                }
              } else if (!this.controller.loadingInitial && this.captureCount() === 0) {
                ListItem() {
                  EmptyPanel({ icon: '▣', title: tr('暂无拍摄记录', 'No capture records'),
                    message: this.project!.lifecycleStatus === ProjectLifecycleStatus.ACTIVE ?
                      tr('填写现场信息并调用系统相机拍摄第一张工程记录。',
                        'Enter the site details and use the system camera for the first record.') :
                      tr('该项目当前没有记录。', 'This project has no records.') })
                }
              } else {
                LazyForEach(this.controller.data, (capture: CaptureRecord) => {
                  ListItem() {
                    CaptureCard({ capture: capture, selectionMode: this.selectionMode,
                      selected: this.selectedIds.indexOf(capture.id) >= 0,
                      onOpen: (): void => this.openCapture(capture),
                      onToggle: (): void => this.toggleCapture(capture.id) })
                  }
                }, (capture: CaptureRecord): string => capture.id)
              }
              if (this.captureCount() > 0 && (this.controller.loadingInitial || this.controller.loadingMore)) {
                ListItem() { LoadingProgress().width(30).height(30).color(UiTokens.PRIMARY) }
              }
              if (this.captureCount() > 0 && this.controller.failed) {
                ListItem() {
                  Column() {
                    InlineErrorPanel({ message: tr('记录加载失败，已保留现有内容',
                      'Records could not be loaded. Existing records were kept.'),
                      retryLabel: tr('重试', 'Retry'), onRetry: (): void => { this.retryCaptures(); } })
                  }
                  .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
                  .width('100%')
                }
              }
            }
            .layoutWeight(1).width('100%')
            .padding({ bottom: this.selectionMode ? 132 : 96 })
            .cachedCount(4)
            .edgeEffect(EdgeEffect.Spring)
            .onScrollIndex((start: number, _end: number): void => {
              if (this.restorePending) {
                return;
              }
              this.savedFirstVisibleIndex = Math.max(0, start);
              this.saveDetailState();
            })
            .onReachEnd((): void => { this.controller.loadNext(); })
          } else if (!this.projectLoading) {
            EmptyPanel({ icon: '!', title: tr('项目不存在', 'Project not found'),
              message: tr('项目可能已被删除，请返回后重试。', 'The project may have been deleted. Go back and try again.'),
              actionLabel: tr('返回', 'Back'), onAction: (): void => { this.pathStack.pop(); } })
          }
        }
        .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
        if (this.project !== null && this.project!.lifecycleStatus === ProjectLifecycleStatus.ACTIVE &&
          !this.selectionMode) {
          Button(tr('拍摄', 'Capture')).height(54).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor(Color.White).backgroundColor(UiTokens.PRIMARY).borderRadius(27)
            .shadow({ radius: 18, color: '#40176B55', offsetY: 7 })
            .margin({ right: 18, bottom: 18 }).align(Alignment.BottomEnd)
            .onClick((): void => { this.pathStack.pushPathByName(Routes.CAPTURE_FORM, null); })
        }
        if (this.selectionMode) {
          this.batchBar()
        }
      }.width('100%').height('100%')
    }
    .hideTitleBar(true)
  }
}

@Component
export struct ProjectSettingsScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private project: ProjectRecord | null = null;
  @State private watermarkOpacity: number = 0.78;
  @State private fontScale: number = 1.0;
  @State private watermarkPosition: string = 'bottomLeft';
  @State private accent: number = 0xFF2E7D61;
  @State private message: string = '';

  aboutToAppear(): void {
    AppRuntime.require().database.projectById(AppRuntime.require().selectedProjectId)
      .then((project: ProjectRecord | null): void => {
        this.project = project;
        if (project !== null) {
          this.watermarkOpacity = project.watermarkOpacity;
          this.fontScale = project.watermarkFontScale;
          this.watermarkPosition = project.watermarkPosition;
          this.accent = project.watermarkAccentColorArgb;
        }
      });
  }

  private async save(): Promise<void> {
    if (this.project === null) {
      return;
    }
    await AppRuntime.require().database.updateProject(this.project.id, this.project.description,
      this.watermarkPosition, this.watermarkOpacity, this.accent, this.fontScale);
    AppRuntime.require().notifyDataChanged();
    this.message = tr('已保存；新拍照片和重新生成的成片会使用这些设置',
      'Saved. New photos and regenerated images will use these settings.');
  }

  @Builder
  private colorChoice(value: number, color: string) {
    Button()
      .width(46).height(46).borderRadius(23).backgroundColor(color)
      .border({ width: this.accent === value ? 4 : 1,
        color: this.accent === value ? Color.White : '#33000000' })
      .shadow({ radius: this.accent === value ? 8 : 0, color: '#33000000' })
      .onClick((): void => { this.accent = value; })
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('此项目水印设置', 'Project watermark settings'), showBack: true,
          onBack: (): void => { this.pathStack.pop(); }, actionLabel: tr('保存', 'Save'),
          onAction: (): void => { this.save(); } })
        Scroll() {
          Column({ space: 18 }) {
            Column({ space: 8 }) {
            Text(tr('水印位置', 'Watermark position')).fontSize(15).fontWeight(FontWeight.Bold).width('100%')
              Row({ space: 8 }) {
              Button(tr('左下', 'Bottom left')).layoutWeight(1).height(44)
                  .backgroundColor(this.watermarkPosition === 'bottomLeft' ? UiTokens.PRIMARY_CONTAINER : '#E8EFEB')
                  .fontColor(UiTokens.TEXT).onClick((): void => { this.watermarkPosition = 'bottomLeft'; })
              Button(tr('右下', 'Bottom right')).layoutWeight(1).height(44)
                  .backgroundColor(this.watermarkPosition === 'bottomRight' ? UiTokens.PRIMARY_CONTAINER : '#E8EFEB')
                  .fontColor(UiTokens.TEXT).onClick((): void => { this.watermarkPosition = 'bottomRight'; })
              }.width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 6 }) {
              Row() {
              Text(tr('透明度', 'Opacity')).fontSize(15).fontWeight(FontWeight.Bold).layoutWeight(1)
                Text(`${Math.round(this.watermarkOpacity * 100)}%`).fontSize(14).fontColor(UiTokens.PRIMARY)
              }.width('100%')
              Slider({ value: this.watermarkOpacity, min: 0.35, max: 1.0, step: 0.05 })
                .selectedColor(UiTokens.PRIMARY).onChange((value: number): void => { this.watermarkOpacity = value; })
            }.width('100%')
            Column({ space: 6 }) {
              Row() {
              Text(tr('字体大小', 'Font size')).fontSize(15).fontWeight(FontWeight.Bold).layoutWeight(1)
                Text(`${Math.round(this.fontScale * 100)}%`).fontSize(14).fontColor(UiTokens.PRIMARY)
              }.width('100%')
              Slider({ value: this.fontScale, min: 0.75, max: 1.6, step: 0.05 })
                .selectedColor(UiTokens.PRIMARY).onChange((value: number): void => { this.fontScale = value; })
            }.width('100%')
            Column({ space: 10 }) {
            Text(tr('强调色', 'Accent color')).fontSize(15).fontWeight(FontWeight.Bold).width('100%')
              Row({ space: 12 }) {
                this.colorChoice(0xFF2E7D61, '#2E7D61')
                this.colorChoice(0xFF1565C0, '#1565C0')
                this.colorChoice(0xFFC05A24, '#C05A24')
                this.colorChoice(0xFF7B4DA8, '#7B4DA8')
                this.colorChoice(0xFF37474F, '#37474F')
              }.width('100%')
            }.width('100%')
            Column({ space: 8 }) {
              Text(tr('工程印记预览', 'SiteMark preview')).fontSize(12).fontColor('#D6EEE4')
              Text(this.project?.name ?? tr('项目名称', 'Project name')).fontSize(18 * this.fontScale)
                .fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
              Text(tr('工程部位 · 工作内容\n拍摄人  2026-08-20 12:00',
                'Location · Work\nPhotographer  2026-08-20 12:00'))
                .fontSize(13 * this.fontScale).fontColor(Color.White).lineHeight(19 * this.fontScale)
                .width('100%')
            }
            .padding(18)
            .width('100%')
            .opacity(this.watermarkOpacity)
            .backgroundColor('#CC17201C')
            .border({ width: 3, color: this.accent })
            .borderRadius(16)
            if (this.message.length > 0) {
              Text(this.message).fontSize(13).fontColor(UiTokens.SUCCESS).width('100%')
            }
          }
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 12, bottom: 40 })
          .width('100%')
        }.layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }
    .hideTitleBar(true)
  }
}

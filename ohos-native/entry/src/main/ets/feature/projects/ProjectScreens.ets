import { AppRuntime } from '../../app/AppRuntime';
import { Routes } from '../../app/Routes';
import { CaptureFilter, CapturePage, CapturePageCursor, CaptureRecord, ProjectRecord,
  ProjectSummary } from '../../domain/Models';
import { ProjectLifecycleStatus } from '../../domain/StateMachine';
import { CaptureCard } from '../records/RecordComponents';
import { RecordBatchLayoutPolicy, RecordNavigationSeedStore,
  RecordSelectionCoordinator } from '../records/RecordUiCoordinator';
import { AppTopBar, BatchActionBar, BatchActionItem, EmptyPanel, InlineErrorPanel, ListSkeleton,
  SectionHeader } from '../../shared/AppComponents';
import { FormField, FormTextArea } from '../../shared/FormComponents';
import { formatDateTime, imageUri, lifecycleLabel } from '../../shared/Formatters';
import { UiTokens } from '../../shared/UiTokens';
import { ProjectBackupService } from '../backup/BackupService';
import { AppText, tr } from '../../shared/AppText';
import { LazyListDataSource } from '../../shared/LazyListDataSource';
import { ListPageCoordinator } from '../../shared/ListPageCoordinator';
import { clampFirstVisibleIndex } from '../../shared/ScreenStateStore';
import { RootShellPolicy } from '../../shared/RootShellPolicy';
import { ProjectCard } from './ProjectComponents';
import { CapturePageLoader, CapturePagedController } from '../records/CapturePagedController';
import {
  ProjectFormCopy,
  ProjectFormMetrics,
  ProjectSaveFeedback,
  projectFormCopy,
  projectNameValidationError,
  projectSaveFeedback,
  selectionKey,
  selectionVisual,
  WatermarkAccentChoice,
  watermarkAccentChoices,
  WatermarkPreviewLayer,
  watermarkPreviewLayer,
  WatermarkPreviewLayout,
  watermarkPreviewLayout,
  WatermarkPositionChoice,
  watermarkPositionChoices,
  WatermarkPreviewStyle,
} from './ProjectFormPolicy';
import { ScreenLifecycleActionCoordinator } from '../../shared/ScreenActionCoordinator';
import { BackAction, BackCoordinator, RootBackDispatcher,
  ScreenLoadCoordinator } from '../../shared/ScreenUiStabilityCoordinator';
import { AppDatabaseProjectSaveStore, ProjectDetailMutationPolicy, ProjectEditorSaveExecutor,
  ProjectEditorSaveSnapshot, ProjectOperationCoordinator, ProjectOperationKind,
  WatermarkSaveSnapshot } from './ProjectEditStability';

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
  private rootBackToken: number = -1;
  private readonly pageState: ListPageCoordinator = new ListPageCoordinator();
  private readonly refreshListener: () => void = (): void => { this.load(); };
  private readonly memoryListener: (level: number) => void = (_level: number): void => {
    this.pageState.requestSafeReload();
  };

  aboutToAppear(): void {
    if (!this.pageState.activate()) {
      return;
    }
    const runtime = AppRuntime.require();
    const restored = runtime.screenState.project(this.lifecycle);
    this.searchText = restored.searchText;
    this.savedFirstVisibleIndex = restored.firstVisibleIndex;
    this.pageState.beginRestore();
    this.rootBackToken = RootBackDispatcher.register((): boolean => this.handleRootBack());
    runtime.subscribe(this.refreshListener);
    runtime.uiMemory.register(this.memoryListener);
    this.load();
  }

  aboutToDisappear(): void {
    this.deactivatePage();
  }

  private deactivatePage(): void {
    if (!this.pageState.deactivate()) {
      return;
    }
    this.saveProjectState();
    this.cancelTimers();
    RootBackDispatcher.unregister(this.rootBackToken);
    this.rootBackToken = -1;
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
    if (!this.pageState.isRestorePending() || this.projectCount === 0) {
      return;
    }
    this.cancelRestoreTimer();
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (!this.pageState.isActive() || generation !== this.loadGeneration ||
        !this.pageState.isRestorePending() || this.projectCount === 0) {
        return;
      }
      const index = clampFirstVisibleIndex(this.savedFirstVisibleIndex, this.projectCount);
      this.savedFirstVisibleIndex = index;
      this.saveProjectState();
      this.projectScroller.scrollToIndex(index, false, ScrollAlign.START);
      this.pageState.completeRestore();
    }, 0);
  }

  private async load(): Promise<void> {
    if (!this.pageState.isActive()) {
      return;
    }
    this.pageState.consumeSafeReloadRequest();
    const generation = ++this.loadGeneration;
    this.loading = true;
    try {
      const projects = await AppRuntime.require().database.listProjectSummaries(this.lifecycle, this.searchText);
      if (!this.pageState.isActive() || generation !== this.loadGeneration) return;
      this.projectSource.replace(projects);
      this.projectCount = projects.length;
      this.message = '';
      this.scheduleRestore(generation);
    } catch (_) {
      if (this.pageState.isActive() && generation === this.loadGeneration) {
        this.message = tr('项目加载失败，请稍后重试', 'Projects could not be loaded. Try again.');
      }
    } finally {
      if (this.pageState.isActive() && generation === this.loadGeneration) {
        this.loading = false;
      }
    }
  }

  private scheduleSearch(): void {
    if (this.searchTimer >= 0) clearTimeout(this.searchTimer);
    this.savedFirstVisibleIndex = 0;
    this.pageState.beginRestore();
    this.saveProjectState();
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.load();
    }, 250);
  }

  private handleRootBack(): boolean {
    if (this.pathStack.size() > 0 || this.searchText.length === 0) {
      return false;
    }
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.searchText = '';
    this.savedFirstVisibleIndex = 0;
    this.pageState.beginRestore();
    this.saveProjectState();
    this.load();
    return true;
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
    this.pageState.beginRestore();
    this.load();
  }

  @Builder
  private statusChip(label: string, value: ProjectLifecycleStatus) {
    Button(label)
      .height(UiTokens.TOUCH_TARGET)
      .layoutWeight(1)
      .fontSize(14)
      .fontWeight(this.lifecycle === value ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.lifecycle === value ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
      .backgroundColor(this.lifecycle === value ? UiTokens.PRIMARY_CONTAINER : Color.Transparent)
      .borderRadius(UiTokens.TOUCH_TARGET / 2)
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
        .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 6,
          bottom: RootShellPolicy.contentBottomInset() })
        .cachedCount(4)
        .edgeEffect(EdgeEffect.Spring)
        .onScrollIndex((start: number, _end: number): void => {
          if (!this.pageState.canSaveScroll()) {
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
  @State private nameError: string = '';
  @State private editing: boolean = false;
  @State private loading: boolean = false;
  @State private loadError: string = '';
  private readonly loadCoordinator: ScreenLoadCoordinator<ProjectRecord> = new ScreenLoadCoordinator<ProjectRecord>();
  private readonly saveAction: ScreenLifecycleActionCoordinator = new ScreenLifecycleActionCoordinator();
  private projectId: string = '';

  private copy(): ProjectFormCopy {
    return projectFormCopy(AppText.isEnglish());
  }

  aboutToAppear(): void {
    this.loadCoordinator.activate();
    this.saveAction.activate();
    const id = AppRuntime.require().selectedProjectId;
    this.projectId = id;
    this.editing = id.length > 0;
    if (this.editing) {
      this.loadProject();
    }
  }

  aboutToDisappear(): void {
    this.loadCoordinator.deactivate();
    this.saveAction.invalidate();
  }

  private async loadProject(): Promise<void> {
    const token = this.loadCoordinator.begin();
    if (token < 0) return;
    this.loading = true;
    this.loadError = '';
    try {
      const project = await AppRuntime.require().database.projectById(this.projectId);
      if (!this.loadCoordinator.resolve(token, project)) return;
      if (project === null) {
        this.loadError = tr('项目不存在，可能已被删除', 'The project no longer exists');
      } else {
        this.name = project.name;
        this.description = project.description;
      }
    } catch (_) {
      if (this.loadCoordinator.reject(token)) {
        this.loadError = tr('项目资料加载失败，请重试', 'Project details could not be loaded. Try again.');
      }
    } finally {
      if (this.loadCoordinator.isCurrent(token)) this.loading = false;
    }
  }

  private async save(): Promise<void> {
    const actionToken = this.saveAction.begin();
    if (actionToken === null) return;
    const snapshot = new ProjectEditorSaveSnapshot(this.editing, this.projectId, this.name, this.description);
    const validationError = projectNameValidationError(snapshot.name, AppText.isEnglish());
    if (validationError.length > 0) {
      this.nameError = validationError;
      this.message = '';
      this.saveAction.finish(actionToken);
      return;
    }
    this.saving = true;
    try {
      const runtime = AppRuntime.require();
      const store = new AppDatabaseProjectSaveStore(runtime.database);
      const savedProjectId = await ProjectEditorSaveExecutor.persistEditor(store, snapshot);
      runtime.notifyDataChanged();
      if (this.saveAction.isCurrent(actionToken)) {
        if (!snapshot.editing) runtime.selectedProjectId = savedProjectId;
        this.pathStack.pop();
      }
    } catch (error) {
      if (this.saveAction.isCurrent(actionToken)) {
        const text = (error as Error).message;
        const feedback: ProjectSaveFeedback = projectSaveFeedback(text, AppText.isEnglish());
        this.nameError = feedback.nameError;
        this.message = feedback.pageMessage;
      }
    } finally {
      this.saveAction.finish(actionToken);
      if (this.saveAction.isActive() && !this.saveAction.isBusy()) this.saving = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: this.editing ? tr('编辑项目', 'Edit project') : tr('新建项目', 'New project'),
          showBack: true, backAccessibilityText: this.editing ?
            tr('取消编辑并返回项目详情', 'Cancel editing and return to project details') :
            tr('取消新建并返回项目列表', 'Cancel creation and return to projects'),
          onBack: (): void => { this.pathStack.pop(); },
          actionLabel: this.saving ? tr('保存中', 'Saving') : tr('保存', 'Save'), actionEnabled: !this.loading &&
            this.loadError.length === 0 && !this.saving,
          actionAccessibilityText: this.saving ? tr('正在保存项目', 'Saving project') :
            tr('保存项目', 'Save project'),
          onAction: (): void => { this.save(); } })
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).height(36).color(UiTokens.PRIMARY)
            Text(tr('正在加载项目资料…', 'Loading project details…')).fontSize(14)
              .fontColor(UiTokens.TEXT_SECONDARY)
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else if (this.loadError.length > 0) {
          Column() {
            InlineErrorPanel({ message: this.loadError, retryLabel: tr('重试', 'Retry'),
              onRetry: (): void => { this.loadProject(); } })
          }.layoutWeight(1).padding(UiTokens.PAGE_PADDING).width('100%').justifyContent(FlexAlign.Center)
        } else {
        Scroll() {
          Column({ space: 16 }) {
            FormField({
              label: this.copy().nameLabel,
              value: this.name,
              placeholder: this.copy().namePlaceholder,
              required: true,
              error: this.nameError,
              helper: this.copy().nameHelper,
              maxLength: ProjectFormMetrics.PROJECT_NAME_MAX_LENGTH,
              fieldEnabled: !this.saving,
              onChange: (value: string): void => {
                this.name = value;
                this.nameError = '';
                this.message = '';
              },
            })
            FormTextArea({
              label: this.copy().descriptionLabel,
              value: this.description,
              placeholder: this.copy().descriptionPlaceholder,
              helper: this.copy().descriptionHelper,
              maxLength: ProjectFormMetrics.PROJECT_DESCRIPTION_MAX_LENGTH,
              fieldEnabled: !this.saving,
              onChange: (value: string): void => { this.description = value; },
            })
            if (this.message.length > 0) {
              InlineErrorPanel({ message: this.message })
            }
            Text(tr('项目名称必须唯一。重命名只影响以后新拍照片，历史编号和文件名不会改变。',
              'Project names must be unique. Renaming only affects future photos; existing numbers and file names stay unchanged.'))
              .fontSize(13)
              .fontColor(UiTokens.TEXT_SECONDARY)
              .lineHeight(20)
              .padding(16)
              .width('100%')
              .backgroundColor(UiTokens.SURFACE)
              .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
              .borderRadius(UiTokens.CONTROL_RADIUS)
          }
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 12, bottom: 40 })
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Start)
        }
        .layoutWeight(1)
        }
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
  @State private projectLoadError: string = '';
  @State private controllerRevision: number = 0;
  @State private confirmDelete: boolean = false;
  @State private message: string = '';
  @State private selectionMode: boolean = false;
  @State private selectedIds: string[] = [];
  @State private allSelected: boolean = false;
  @State private batchBusy: boolean = false;
  @State private mutationBusy: boolean = false;
  @State private confirmBatchDelete: boolean = false;
  @State private searchText: string = '';
  @State private filterOpen: boolean = false;
  @State private yearText: string = '';
  @State private monthText: string = '';
  @State private dayText: string = '';
  private readonly selection: RecordSelectionCoordinator = new RecordSelectionCoordinator();
  private readonly controller: CapturePagedController = new CapturePagedController(new RuntimeCapturePageLoader(),
    (): void => { this.controllerRevision += 1; });
  private readonly detailScroller: Scroller = new Scroller();
  private searchTimer: number = -1;
  private restoreTimer: number = -1;
  private readonly projectLoad: ScreenLoadCoordinator<ProjectRecord> = new ScreenLoadCoordinator<ProjectRecord>();
  private readonly projectOperations: ProjectOperationCoordinator = new ProjectOperationCoordinator();
  private contentGeneration: number = 0;
  private savedFirstVisibleIndex: number = 0;
  private readonly pageState: ListPageCoordinator = new ListPageCoordinator();
  private projectId: string = '';
  private readonly refreshListener: () => void = (): void => { this.refreshContent(); };
  private readonly memoryListener: (level: number) => void = (_level: number): void => {
    this.pageState.requestSafeReload();
  };

  aboutToAppear(): void {
    const runtime = AppRuntime.require();
    this.projectId = runtime.selectedProjectId;
    const restored = runtime.screenState.projectDetail(this.projectId);
    this.searchText = restored.filter.searchText;
    this.yearText = restored.filter.year > 0 ? restored.filter.year.toString() : '';
    this.monthText = restored.filter.month > 0 ? restored.filter.month.toString() : '';
    this.dayText = restored.filter.day > 0 ? restored.filter.day.toString() : '';
    this.savedFirstVisibleIndex = restored.firstVisibleIndex;
    this.pageState.beginRestore();
    this.activatePage();
  }

  private activatePage(): void {
    if (!this.pageState.activate()) {
      return;
    }
    this.projectLoad.activate();
    this.projectOperations.activate();
    this.reconcileProjectOperationBusyState();
    const runtime = AppRuntime.require();
    this.pageState.beginRestore();
    this.pageState.consumeSafeReloadRequest();
    runtime.subscribe(this.refreshListener);
    runtime.uiMemory.register(this.memoryListener);
    this.refreshContent();
  }

  aboutToDisappear(): void {
    this.deactivatePage();
  }

  private deactivatePage(): void {
    if (!this.pageState.deactivate()) {
      return;
    }
    this.saveDetailState();
    this.cancelTimers();
    this.projectLoad.deactivate();
    this.projectOperations.invalidate();
    this.contentGeneration += 1;
    this.selection.invalidatePending();
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
    if (this.projectLoadError.length > 0) count += 1;
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
    this.selection.resetForFilterChange();
    this.syncSelection();
    this.savedFirstVisibleIndex = 0;
    this.pageState.beginRestore();
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
    if (!this.pageState.isActive()) {
      return;
    }
    this.loadProject();
    this.resetCaptures();
  }

  private async loadProject(): Promise<void> {
    if (!this.pageState.isActive()) {
      return;
    }
    const generation = this.projectLoad.begin();
    if (generation < 0) return;
    this.projectLoadError = '';
    if (this.project === null) {
      this.projectLoading = true;
    }
    try {
      const project = await AppRuntime.require().database.projectById(this.projectId);
      if (!this.pageState.isActive() || !this.projectLoad.resolve(generation, project)) {
        return;
      }
      this.project = project;
      if (project !== null && !this.controller.loadingInitial && !this.controller.failed) {
        this.scheduleDetailRestore(this.contentGeneration);
      }
    } catch (_) {
      if (this.pageState.isActive() && this.projectLoad.reject(generation)) {
        this.projectLoadError = tr('项目资料加载失败，请重试', 'Project details could not be loaded. Try again.');
      }
    } finally {
      if (this.pageState.isActive() && this.projectLoad.isCurrent(generation)) {
        this.projectLoading = false;
      }
    }
  }

  private async resetCaptures(): Promise<void> {
    if (!this.pageState.isActive()) {
      return;
    }
    const generation = ++this.contentGeneration;
    await this.controller.reset(this.currentFilter());
    if (!this.pageState.isActive() || generation !== this.contentGeneration || this.controller.failed ||
      this.project === null) {
      return;
    }
    this.scheduleDetailRestore(generation);
  }

  private async retryCaptures(): Promise<void> {
    if (this.pageBusy() || !this.pageState.isActive()) {
      return;
    }
    const generation = ++this.contentGeneration;
    await this.controller.retry();
    if (!this.pageState.isActive() || generation !== this.contentGeneration || this.controller.failed ||
      this.project === null) {
      return;
    }
    this.scheduleDetailRestore(generation);
  }

  private scheduleDetailRestore(generation: number): void {
    if (!this.pageState.isRestorePending() || this.captureCount() === 0) {
      return;
    }
    this.cancelRestoreTimer();
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (!this.pageState.isActive() || generation !== this.contentGeneration ||
        !this.pageState.isRestorePending() ||
        this.captureCount() === 0) {
        return;
      }
      const index = clampFirstVisibleIndex(this.savedFirstVisibleIndex, this.detailItemCount());
      this.savedFirstVisibleIndex = index;
      this.saveDetailState();
      this.detailScroller.scrollToIndex(index, false, ScrollAlign.START);
      this.pageState.completeRestore();
    }, 0);
  }

  private openCapture(capture: CaptureRecord): void {
    if (this.pageBusy()) return;
    const path = capture.renderedPath.length > 0 ? capture.renderedPath : capture.originalPath;
    RecordNavigationSeedStore.put(capture, path.length > 0 ? imageUri(path) : '');
    AppRuntime.require().selectedCaptureId = capture.id;
    this.pathStack.pushPathByName(Routes.CAPTURE_DETAIL, null);
  }

  private setSelectionMode(enabled: boolean): void {
    if (this.pageBusy()) return;
    if (enabled) this.selection.enter();
    else this.selection.exit();
    this.syncSelection();
  }

  private pageBusy(): boolean {
    return this.batchBusy || this.mutationBusy;
  }

  private canMutateProject(): boolean {
    return ProjectDetailMutationPolicy.enabled(this.pageBusy() || this.selectionMode, this.project !== null);
  }

  private beginProjectMutation(): number | null {
    if (!this.canMutateProject()) return null;
    const token = this.projectOperations.begin(ProjectOperationKind.MUTATION);
    this.reconcileProjectOperationBusyState();
    return token;
  }

  private finishProjectMutation(token: number): void {
    this.projectOperations.finish(token);
    this.reconcileProjectOperationBusyState();
  }

  private reconcileProjectOperationBusyState(): void {
    if (!this.pageState.isActive()) return;
    const state = this.projectOperations.uiState();
    this.batchBusy = state.batchBusy;
    this.mutationBusy = state.mutationBusy;
  }

  private openProjectSettings(): void {
    if (!this.canMutateProject()) return;
    this.pathStack.pushPathByName(Routes.PROJECT_SETTINGS, null);
  }

  private editProject(): void {
    if (!this.canMutateProject()) return;
    this.pathStack.pushPathByName(Routes.PROJECT_EDITOR, null);
  }

  private beginCapture(): void {
    if (!this.canMutateProject()) return;
    this.pathStack.pushPathByName(Routes.CAPTURE_FORM, null);
  }

  private exitSelectionAfterBatch(): void {
    this.selection.exit();
    this.syncSelection();
  }

  private syncSelection(): void {
    this.selectionMode = this.selection.selectionMode;
    this.selectedIds = this.selection.selectedIds.slice();
    this.allSelected = this.selection.allSelected;
    this.confirmBatchDelete = this.selection.confirmDelete;
  }

  private batchFontScale(): number {
    return AppRuntime.require().context.config.fontSizeScale ?? 1;
  }

  private toggleCapture(captureId: string): void {
    if (this.pageBusy()) return;
    this.selection.toggle(captureId);
    this.syncSelection();
  }

  private async toggleAll(): Promise<void> {
    if (this.pageBusy() || this.project === null) return;
    if (this.selection.allSelected) {
      this.selection.deselectAll();
      this.syncSelection();
      return;
    }
    const actionToken = this.projectOperations.begin(ProjectOperationKind.BATCH);
    if (actionToken === null) return;
    const requestedFilter = this.currentFilter();
    const token = this.selection.beginSelectAll(requestedFilter);
    this.reconcileProjectOperationBusyState();
    try {
      const ids = await AppRuntime.require().database.captureIds(requestedFilter);
      if (!this.pageState.isActive() || !this.projectOperations.isCurrent(actionToken) ||
        !this.selection.commitSelectAll(token, this.currentFilter(), ids)) {
        return;
      }
      this.syncSelection();
    } catch (_) {
      if (this.pageState.isActive() && this.projectOperations.isCurrent(actionToken) &&
        this.selection.isSelectAllCurrent(token, this.currentFilter())) {
        this.message = tr('无法全选项目记录，请重试', 'Could not select every project record. Try again.');
      }
    } finally {
      this.projectOperations.finish(actionToken);
      this.reconcileProjectOperationBusyState();
    }
  }

  private async batchExport(): Promise<void> {
    if (this.selectedIds.length === 0) {
      this.message = tr('请先选择照片', 'Select photos first');
      return;
    }
    const actionToken = this.projectOperations.begin(ProjectOperationKind.BATCH);
    if (actionToken === null) return;
    const ids = this.selectedIds.slice();
    this.reconcileProjectOperationBusyState();
    try {
      const service = new ProjectBackupService(AppRuntime.require());
      const result = await service.exportSelection(ids, false);
      const saved = await service.saveAs(result);
      if (this.pageState.isActive() && this.projectOperations.isCurrent(actionToken)) {
        this.message = saved ? tr('所选照片已导出到你选择的位置',
          'Selected photos were exported to your chosen location') :
          tr('已取消保存导出文件', 'Export save was cancelled');
      }
    } catch (_) {
      if (this.pageState.isActive() && this.projectOperations.isCurrent(actionToken)) {
        this.message = tr('所选照片暂时无法导出，请检查记录状态和存储空间',
          'Selected photos could not be exported. Check their status and available storage.');
      }
    } finally {
      this.projectOperations.finish(actionToken);
      this.reconcileProjectOperationBusyState();
    }
  }

  private async runBatch(action: (id: string) => Promise<void>, success: string): Promise<void> {
    const ids = this.selectedIds.slice();
    if (ids.length === 0) {
      this.message = tr('请先选择照片', 'Select photos first');
      return;
    }
    const actionToken = this.projectOperations.begin(ProjectOperationKind.BATCH);
    if (actionToken === null) return;
    this.reconcileProjectOperationBusyState();
    try {
      let succeeded = 0;
      for (const id of ids) {
        try {
          await action(id);
          succeeded += 1;
        } catch (_) {
        }
      }
      if (this.pageState.isActive() && this.projectOperations.isCurrent(actionToken)) {
        this.message = succeeded === ids.length ? success :
        tr(`已完成 ${succeeded}/${ids.length} 项`, `Completed ${succeeded}/${ids.length}`);
        this.exitSelectionAfterBatch();
        await this.resetCaptures();
      }
    } finally {
      this.projectOperations.finish(actionToken);
      this.reconcileProjectOperationBusyState();
    }
  }

  private consumeBack(): boolean {
    const action = BackCoordinator.next({
      busy: this.pageBusy(),
      selection: this.selectionMode,
      confirmation: this.confirmDelete,
      filter: this.filterOpen,
      search: this.searchText.length > 0,
    });
    if (action === BackAction.CONSUME) return true;
    if (action === BackAction.EXIT_SELECTION) {
      this.setSelectionMode(false);
      return true;
    }
    if (action === BackAction.CLOSE_CONFIRMATION) {
      this.confirmDelete = false;
      return true;
    }
    if (action === BackAction.CLOSE_FILTER) {
      this.filterOpen = false;
      this.saveDetailState();
      return true;
    }
    if (action === BackAction.CLEAR_SEARCH) {
      this.searchText = '';
      this.markFilterChanged();
      this.resetCaptures();
      return true;
    }
    return false;
  }

  private navigateBack(): void {
    if (!this.consumeBack()) this.pathStack.pop();
  }

  private backAccessibilityText(): string {
    const action = BackCoordinator.next({
      busy: this.pageBusy(),
      selection: this.selectionMode,
      confirmation: this.confirmDelete,
      filter: this.filterOpen,
      search: this.searchText.length > 0,
    });
    if (action === BackAction.CONSUME) return tr('批量操作进行中', 'Batch operation in progress');
    if (action === BackAction.EXIT_SELECTION) return tr('取消照片选择', 'Cancel photo selection');
    if (action === BackAction.CLOSE_CONFIRMATION) return tr('关闭删除确认', 'Close delete confirmation');
    if (action === BackAction.CLOSE_FILTER) return tr('收起筛选', 'Hide filters');
    if (action === BackAction.CLEAR_SEARCH) return tr('清除搜索', 'Clear search');
    return tr('返回项目列表', 'Back to projects');
  }

  private async batchDelete(): Promise<void> {
    if (this.selectedIds.length === 0) {
      this.message = tr('请先选择照片', 'Select photos first');
      return;
    }
    if (!this.selection.requestPermanentDelete()) {
      this.syncSelection();
      this.message = tr(`再次点击“确认删除”将永久删除已选 ${this.selectedIds.length} 条记录`,
        `Tap “Confirm delete” again to permanently delete ${this.selectedIds.length} selected records`);
      return;
    }
    await this.runBatch((id: string): Promise<void> => AppRuntime.require().deleteCapture(id),
      tr('所选记录已删除', 'Selected records deleted'));
  }

  @Builder
  private batchBar() {
    Column() {
      BatchActionBar({ selectedLabel: tr(`已选 ${this.selectedIds.length} 张`,
        `${this.selectedIds.length} selected`),
        actionHeight: RecordBatchLayoutPolicy.actionHeight(this.batchFontScale()),
        actionLabelMaxLines: RecordBatchLayoutPolicy.actionLabelMaxLines(), actions: [
          new BatchActionItem('export', '⇩', tr('导出', 'Export'), false, this.pageBusy(),
            tr('导出所选照片', 'Export selected photos')),
          new BatchActionItem('save', '▣', tr('再次保存', 'Save again'), false, this.pageBusy(),
            tr('将所选水印照片再次保存到相册', 'Save selected watermarked photos to the gallery again')),
          new BatchActionItem('clear', '⌫', tr('清原图', 'Clear original'), false, this.pageBusy(),
            tr('清理所选照片的原图', 'Clear originals for selected photos')),
          new BatchActionItem('delete', '×', this.confirmBatchDelete ? tr('确认删除', 'Confirm delete') :
            tr('删除', 'Delete'), true, this.pageBusy(),
            this.confirmBatchDelete ? tr('确认永久删除所选照片，此操作无法撤销',
              'Confirm permanent deletion of selected photos; this action cannot be undone') :
              tr('永久删除所选照片，此操作无法撤销',
                'Permanently delete selected photos; this action cannot be undone')),
        ], onAction: (id: string): void => {
          if (id === 'export') this.batchExport();
          else if (id === 'save') this.runBatch((captureId: string): Promise<void> =>
            AppRuntime.require().republishCapture(captureId), tr('已再次保存到相册', 'Saved to the gallery'));
          else if (id === 'clear') this.runBatch((captureId: string): Promise<void> =>
            AppRuntime.require().clearOriginal(captureId), tr('原图清理已完成', 'Original cleanup completed'));
          else if (id === 'delete') this.batchDelete();
        } })
        .height(RecordBatchLayoutPolicy.barHeight(this.batchFontScale()))
    }
    .margin({ left: 16, right: 16, bottom: RecordBatchLayoutPolicy.bottomMargin() })
    .width('100%')
  }

  @Builder
  private recordFilterPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.yearText, placeholder: tr('年', 'Year') }).layoutWeight(1)
          .height(RecordBatchLayoutPolicy.filterControlHeight())
          .enabled(!this.pageBusy())
          .type(InputType.Number)
          .onChange((value: string): void => { this.yearText = value; this.markFilterChanged(); })
        TextInput({ text: this.monthText, placeholder: tr('月', 'Month') }).layoutWeight(1)
          .height(RecordBatchLayoutPolicy.filterControlHeight())
          .enabled(!this.pageBusy())
          .type(InputType.Number)
          .onChange((value: string): void => { this.monthText = value; this.markFilterChanged(); })
        TextInput({ text: this.dayText, placeholder: tr('日', 'Day') }).layoutWeight(1)
          .height(RecordBatchLayoutPolicy.filterControlHeight())
          .enabled(!this.pageBusy())
          .type(InputType.Number)
          .onChange((value: string): void => { this.dayText = value; this.markFilterChanged(); })
      }.width('100%')
      Row({ space: 8 }) {
          Button(tr('清除日期', 'Clear date')).layoutWeight(1)
            .height(RecordBatchLayoutPolicy.filterControlHeight())
            .enabled(!this.pageBusy())
            .backgroundColor(UiTokens.CONTROL).fontColor(UiTokens.TEXT)
          .onClick((): void => {
            this.yearText = ''; this.monthText = ''; this.dayText = '';
            this.markFilterChanged();
            this.resetCaptures();
          })
          Button(tr('应用筛选', 'Apply filters')).layoutWeight(1)
            .height(RecordBatchLayoutPolicy.filterControlHeight())
            .enabled(!this.pageBusy())
            .backgroundColor(UiTokens.PRIMARY).fontColor(Color.White)
          .onClick((): void => { this.filterOpen = false; this.markFilterChanged(); this.resetCaptures(); })
      }.width('100%')
    }
    .padding(14).margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
    .backgroundColor(UiTokens.GLASS_STRONG).borderRadius(20).width(`calc(100% - ${UiTokens.PAGE_PADDING * 2}vp)`)
  }

  private async setLifecycle(target: ProjectLifecycleStatus): Promise<void> {
    if (this.project === null) return;
    const projectId = this.project.id;
    const operationToken = this.beginProjectMutation();
    if (operationToken === null) return;
    try {
      await AppRuntime.require().database.setProjectLifecycle(projectId, target, true);
      AppRuntime.require().notifyDataChanged();
      if (this.pageState.isActive() && this.projectOperations.isCurrent(operationToken)) {
        await this.loadProject();
        if (this.pageState.isActive() && this.projectOperations.isCurrent(operationToken)) {
          await this.resetCaptures();
        }
      }
    } catch (_) {
      if (this.pageState.isActive() && this.projectOperations.isCurrent(operationToken)) {
        this.message = tr('有照片仍在处理中，暂时不能更改项目状态',
          'Project status cannot change while photos are processing');
      }
    } finally {
      this.finishProjectMutation(operationToken);
    }
  }

  private async togglePinned(): Promise<void> {
    if (this.project === null) return;
    const projectId = this.project.id;
    const pinned = !this.project.isPinned;
    const operationToken = this.beginProjectMutation();
    if (operationToken === null) return;
    try {
      await AppRuntime.require().database.setProjectPinned(projectId, pinned);
      AppRuntime.require().notifyDataChanged();
      if (this.pageState.isActive() && this.projectOperations.isCurrent(operationToken)) {
        await this.loadProject();
        if (this.pageState.isActive() && this.projectOperations.isCurrent(operationToken)) {
          await this.resetCaptures();
        }
      }
    } catch (_) {
      if (this.pageState.isActive() && this.projectOperations.isCurrent(operationToken)) {
        this.message = tr('暂时无法更改置顶状态，请重试', 'Could not change the pinned state. Try again.');
      }
    } finally {
      this.finishProjectMutation(operationToken);
    }
  }

  private async deleteProject(): Promise<void> {
    if (this.project === null) return;
    const projectId = this.project.id;
    const operationToken = this.beginProjectMutation();
    if (operationToken === null) return;
    try {
      await AppRuntime.require().deleteProject(projectId);
      if (this.pageState.isActive() && this.projectOperations.isCurrent(operationToken)) this.pathStack.pop();
    } catch (_) {
      if (this.pageState.isActive() && this.projectOperations.isCurrent(operationToken)) {
        this.message = tr('有照片仍在处理中，项目暂时不能删除',
          'The project cannot be deleted while photos are processing');
      }
    } finally {
      this.finishProjectMutation(operationToken);
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
          .height(UiTokens.TOUCH_TARGET).layoutWeight(1).fontSize(13).backgroundColor(UiTokens.ACCENT_SURFACE)
          .fontColor(UiTokens.PRIMARY).borderRadius(UiTokens.CONTROL_RADIUS)
          .enabled(this.canMutateProject())
          .accessibilityText(this.project!.isPinned ? tr('取消置顶项目', 'Unpin project') :
            tr('置顶项目', 'Pin project'))
          .onClick((): void => { this.togglePinned(); })
        Button(tr('此项目水印设置', 'Project watermark settings'))
          .height(UiTokens.TOUCH_TARGET).layoutWeight(2).fontSize(13).backgroundColor(UiTokens.ACCENT_SURFACE)
          .fontColor(UiTokens.PRIMARY).borderRadius(UiTokens.CONTROL_RADIUS)
          .enabled(this.canMutateProject())
          .accessibilityText(tr('打开此项目水印设置', 'Open project watermark settings'))
          .onClick((): void => { this.openProjectSettings(); })
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
            backAccessibilityText: this.backAccessibilityText(), onBack: (): void => { this.navigateBack(); },
            actionLabel: this.selectionMode ? tr('完成', 'Done') : tr('编辑', 'Edit'),
            actionEnabled: this.project !== null && !this.pageBusy(),
            onAction: (): void => { if (this.selectionMode) this.setSelectionMode(false);
              else this.editProject(); } })
          if (this.project !== null) {
            List({ space: 10, scroller: this.detailScroller }) {
              ListItem() { this.projectSummary() }
              if (this.projectLoadError.length > 0) {
                ListItem() {
                  Column() {
                    InlineErrorPanel({ message: this.projectLoadError, retryLabel: tr('重试', 'Retry'),
                      onRetry: (): void => { if (!this.pageBusy()) this.loadProject(); } })
                  }.padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING }).width('100%')
                }
              }
              ListItem() { SectionHeader({ title: tr('项目操作', 'Project actions') }) }
              ListItem() {
                Row({ space: 8 }) {
                  if (this.project!.lifecycleStatus !== ProjectLifecycleStatus.ACTIVE) {
                    Button() {
                      Text(tr('恢复进行中', 'Reopen')).fontSize(12).fontColor(UiTokens.PRIMARY)
                        .maxLines(2).textAlign(TextAlign.Center)
                    }
                    .layoutWeight(1).height(UiTokens.TOUCH_TARGET).backgroundColor(UiTokens.ACCENT_SURFACE)
                    .enabled(this.canMutateProject())
                    .onClick((): void => { this.setLifecycle(ProjectLifecycleStatus.ACTIVE); })
                  } else {
                    Button() {
                      Text(tr('标记完成', 'Mark completed')).fontSize(12).fontColor(UiTokens.PRIMARY)
                        .maxLines(2).textAlign(TextAlign.Center)
                    }
                    .layoutWeight(1).height(UiTokens.TOUCH_TARGET).backgroundColor(UiTokens.ACCENT_SURFACE)
                    .enabled(this.canMutateProject())
                    .onClick((): void => { this.setLifecycle(ProjectLifecycleStatus.COMPLETED); })
                  }
                  if (this.project!.lifecycleStatus !== ProjectLifecycleStatus.ARCHIVED) {
                    Button() {
                      Text(tr('归档', 'Archive')).fontSize(12).fontColor(UiTokens.PRIMARY)
                        .maxLines(2).textAlign(TextAlign.Center)
                    }
                    .layoutWeight(1).height(UiTokens.TOUCH_TARGET).backgroundColor(UiTokens.ACCENT_SURFACE)
                    .enabled(this.canMutateProject())
                    .onClick((): void => { this.setLifecycle(ProjectLifecycleStatus.ARCHIVED); })
                  }
                  Button() {
                    Text(tr('删除项目', 'Delete project')).fontSize(12).fontColor(UiTokens.DANGER)
                      .maxLines(2).textAlign(TextAlign.Center)
                  }
                  .layoutWeight(1).height(UiTokens.TOUCH_TARGET).backgroundColor(UiTokens.DANGER_CONTAINER)
                  .enabled(this.canMutateProject())
                  .accessibilityText(tr('删除项目，永久删除本机项目记录',
                    'Delete project, permanently delete on-device project records'))
                  .onClick((): void => {
                    if (this.canMutateProject()) this.confirmDelete = !this.confirmDelete;
                  })
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
                      Button(tr('取消', 'Cancel')).layoutWeight(1).height(UiTokens.TOUCH_TARGET)
                        .enabled(this.canMutateProject())
                        .onClick((): void => { if (this.canMutateProject()) this.confirmDelete = false; })
                      Button(tr('确认删除', 'Confirm delete')).layoutWeight(1).height(UiTokens.TOUCH_TARGET)
                        .backgroundColor(UiTokens.DANGER)
                        .fontColor(Color.White)
                        .enabled(this.canMutateProject())
                        .accessibilityText(tr('确认永久删除本机项目记录；不处理已保存到相册的照片',
                          'Confirm permanent deletion of on-device project records; gallery photos remain'))
                        .onClick((): void => { this.deleteProject(); })
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
                    .enabled(!this.pageBusy())
                    .onChange((value: string): void => { this.searchText = value; this.scheduleSearch(); })
                  Row({ space: 8 }) {
                    Button(this.filterOpen ? tr('收起筛选', 'Hide filters') : tr('筛选', 'Filter'))
                      .height(RecordBatchLayoutPolicy.filterControlHeight()).fontSize(13).fontColor(UiTokens.PRIMARY)
                      .backgroundColor(UiTokens.ACCENT_SURFACE)
                      .enabled(!this.pageBusy())
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
                      .height(UiTokens.TOUCH_TARGET).fontSize(12)
                      .fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.ACCENT_SURFACE)
                      .enabled(!this.pageBusy())
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
            .padding({ bottom: RecordBatchLayoutPolicy.listBottomPadding(this.selectionMode,
              this.batchFontScale()) })
            .cachedCount(4)
            .edgeEffect(EdgeEffect.Spring)
            .onScrollIndex((start: number, _end: number): void => {
              if (!this.pageState.canSaveScroll()) {
                return;
              }
              this.savedFirstVisibleIndex = Math.max(0, start);
              this.saveDetailState();
            })
            .onReachEnd((): void => { this.controller.loadNext(); })
          } else if (this.projectLoadError.length > 0) {
            Column() {
              InlineErrorPanel({ message: this.projectLoadError, retryLabel: tr('重试', 'Retry'),
                onRetry: (): void => { this.loadProject(); } })
            }.layoutWeight(1).padding(UiTokens.PAGE_PADDING).width('100%').justifyContent(FlexAlign.Center)
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
            .enabled(this.canMutateProject())
            .onClick((): void => { this.beginCapture(); })
        }
        if (this.selectionMode) {
          this.batchBar()
        }
      }.width('100%').height('100%')
    }
    .hideTitleBar(true)
    .onShown((): void => { this.activatePage(); })
    .onHidden((): void => { this.deactivatePage(); })
    .onBackPressed((): boolean => this.consumeBack())
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
  @State private loading: boolean = true;
  @State private loadError: string = '';
  @State private saving: boolean = false;
  @State private saveError: string = '';
  private readonly loadCoordinator: ScreenLoadCoordinator<ProjectRecord> = new ScreenLoadCoordinator<ProjectRecord>();
  private readonly saveAction: ScreenLifecycleActionCoordinator = new ScreenLifecycleActionCoordinator();
  private projectId: string = '';

  private copy(): ProjectFormCopy {
    return projectFormCopy(AppText.isEnglish());
  }

  private previewLayer(): WatermarkPreviewLayer {
    return watermarkPreviewLayer(this.watermarkOpacity);
  }

  private previewLayout(): WatermarkPreviewLayout {
    return watermarkPreviewLayout(this.fontScale);
  }

  aboutToAppear(): void {
    this.loadCoordinator.activate();
    this.saveAction.activate();
    this.projectId = AppRuntime.require().selectedProjectId;
    this.loadProject();
  }

  aboutToDisappear(): void {
    this.loadCoordinator.deactivate();
    this.saveAction.invalidate();
  }

  private async loadProject(): Promise<void> {
    const token = this.loadCoordinator.begin();
    if (token < 0) return;
    this.loading = true;
    this.loadError = '';
    try {
      const project = await AppRuntime.require().database.projectById(this.projectId);
      if (!this.loadCoordinator.resolve(token, project)) return;
      this.project = project;
      if (project === null) {
        this.loadError = tr('项目不存在，可能已被删除', 'The project no longer exists');
      } else {
        this.watermarkOpacity = project.watermarkOpacity;
        this.fontScale = project.watermarkFontScale;
        this.watermarkPosition = project.watermarkPosition;
        this.accent = project.watermarkAccentColorArgb;
      }
    } catch (_) {
      if (this.loadCoordinator.reject(token)) {
        this.loadError = tr('水印设置加载失败，请重试', 'Watermark settings could not be loaded. Try again.');
      }
    } finally {
      if (this.loadCoordinator.isCurrent(token)) this.loading = false;
    }
  }

  private async save(): Promise<void> {
    if (this.project === null) {
      return;
    }
    const actionToken = this.saveAction.begin();
    if (actionToken === null) return;
    const snapshot = new WatermarkSaveSnapshot(this.project.id, this.watermarkPosition,
      this.watermarkOpacity, this.accent, this.fontScale);
    this.saving = true;
    this.saveError = '';
    this.message = '';
    try {
      const store = new AppDatabaseProjectSaveStore(AppRuntime.require().database);
      await ProjectEditorSaveExecutor.persistWatermark(store, snapshot);
      AppRuntime.require().notifyDataChanged();
      if (this.saveAction.isCurrent(actionToken)) {
        this.message = tr('已保存；新拍照片和重新生成的成片会使用这些设置',
          'Saved. New photos and regenerated images will use these settings.');
      }
    } catch (_) {
      if (this.saveAction.isCurrent(actionToken)) {
        this.saveError = tr('水印设置保存失败，请检查后重试',
          'Watermark settings could not be saved. Check the values and try again.');
      }
    } finally {
      this.saveAction.finish(actionToken);
      if (this.saveAction.isActive() && !this.saveAction.isBusy()) this.saving = false;
    }
  }

  @Builder
  private colorChoice(choice: WatermarkAccentChoice) {
    Button(choice.selected ? '✓' : '')
      .width(48)
      .height(48)
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .borderRadius(24)
      .backgroundColor(choice.color)
      .border({ width: choice.selected ? 3 : 1,
        color: choice.selected ? UiTokens.TEXT : UiTokens.OUTLINE_SUBTLE })
      .shadow({ radius: choice.selected ? 6 : 0, color: UiTokens.CARD_SHADOW })
      .enabled(!this.saving)
      .accessibilityText(choice.accessibilityText)
      .onClick((): void => { this.accent = choice.value; })
  }

  @Builder
  private positionChoice(choice: WatermarkPositionChoice) {
    Button(choice.selected ? `✓  ${choice.label}` : choice.label)
      .layoutWeight(1)
      .height(ProjectFormMetrics.TOUCH_TARGET)
      .fontSize(14)
      .fontWeight(choice.selected ? FontWeight.Bold : FontWeight.Medium)
      .backgroundColor(selectionVisual(choice.selected).backgroundColor)
      .fontColor(choice.selected ? UiTokens.PRIMARY : UiTokens.TEXT)
      .border({ width: selectionVisual(choice.selected).borderWidth,
        color: selectionVisual(choice.selected).borderColor })
      .borderRadius(UiTokens.CONTROL_RADIUS)
      .enabled(!this.saving)
      .accessibilityText(choice.accessibilityText)
      .onClick((): void => { this.watermarkPosition = choice.value; })
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('此项目水印设置', 'Project watermark settings'), showBack: true,
          backAccessibilityText: tr('返回项目详情', 'Back to project details'),
          onBack: (): void => { this.pathStack.pop(); },
          actionLabel: this.saving ? tr('保存中', 'Saving') : tr('保存', 'Save'),
          actionEnabled: !this.loading && this.loadError.length === 0 && !this.saving && this.project !== null,
          actionAccessibilityText: this.saving ? tr('正在保存项目水印设置', 'Saving project watermark settings') :
            tr('保存项目水印设置',
            'Save project watermark settings'),
          onAction: (): void => { this.save(); } })
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).height(36).color(UiTokens.PRIMARY)
            Text(tr('正在加载水印设置…', 'Loading watermark settings…')).fontSize(14)
              .fontColor(UiTokens.TEXT_SECONDARY)
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else if (this.loadError.length > 0) {
          Column() {
            InlineErrorPanel({ message: this.loadError, retryLabel: tr('重试', 'Retry'),
              onRetry: (): void => { this.loadProject(); } })
          }.layoutWeight(1).padding(UiTokens.PAGE_PADDING).width('100%').justifyContent(FlexAlign.Center)
        } else {
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 10 }) {
              Text(this.copy().watermarkPositionLabel)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(UiTokens.TEXT)
                .width('100%')
              Row({ space: 8 }) {
                ForEach(watermarkPositionChoices(AppText.isEnglish(), this.watermarkPosition),
                  (choice: WatermarkPositionChoice) => {
                    this.positionChoice(choice)
                  }, (choice: WatermarkPositionChoice): string => selectionKey(choice.value, choice.selected))
              }.width('100%')
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(UiTokens.SURFACE)
            .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            .borderRadius(UiTokens.CONTROL_RADIUS)
            Column({ space: 12 }) {
              Row() {
                Text(this.copy().opacityLabel).fontSize(15).fontWeight(FontWeight.Bold)
                  .fontColor(UiTokens.TEXT).layoutWeight(1)
                Text(`${Math.round(this.watermarkOpacity * 100)}%`).fontSize(14).fontColor(UiTokens.PRIMARY)
              }.width('100%')
              Slider({ value: this.watermarkOpacity, min: 0.35, max: 1.0, step: 0.05 })
                .height(ProjectFormMetrics.TOUCH_TARGET)
                .enabled(!this.saving)
                .selectedColor(UiTokens.PRIMARY)
                .trackColor(UiTokens.CONTROL)
                .accessibilityText(`${this.copy().opacityLabel}${tr('，', ', ')}` +
                  `${Math.round(this.watermarkOpacity * 100)}%`)
                .onChange((value: number): void => { this.watermarkOpacity = value; })
              Text(this.copy().opacityHelper).fontSize(12).fontColor(UiTokens.TEXT_SECONDARY)
                .lineHeight(17).maxLines(3).width('100%')
              Divider().strokeWidth(1).color(UiTokens.OUTLINE_SUBTLE)
              Row() {
                Text(this.copy().fontScaleLabel).fontSize(15).fontWeight(FontWeight.Bold)
                  .fontColor(UiTokens.TEXT).layoutWeight(1)
                Text(`${Math.round(this.fontScale * 100)}%`).fontSize(14).fontColor(UiTokens.PRIMARY)
              }.width('100%')
              Slider({ value: this.fontScale, min: 0.75, max: 1.6, step: 0.05 })
                .height(ProjectFormMetrics.TOUCH_TARGET)
                .enabled(!this.saving)
                .selectedColor(UiTokens.PRIMARY)
                .trackColor(UiTokens.CONTROL)
                .accessibilityText(`${this.copy().fontScaleLabel}${tr('，', ', ')}` +
                  `${Math.round(this.fontScale * 100)}%`)
                .onChange((value: number): void => { this.fontScale = value; })
              Text(this.copy().fontScaleHelper).fontSize(12).fontColor(UiTokens.TEXT_SECONDARY)
                .lineHeight(17).maxLines(3).width('100%')
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(UiTokens.SURFACE)
            .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            .borderRadius(UiTokens.CONTROL_RADIUS)
            Column({ space: 10 }) {
              Text(this.copy().accentLabel).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor(UiTokens.TEXT).width('100%')
              Row({ space: 12 }) {
                ForEach(watermarkAccentChoices(AppText.isEnglish(), this.accent),
                  (choice: WatermarkAccentChoice) => {
                    this.colorChoice(choice)
                  }, (choice: WatermarkAccentChoice): string =>
                    selectionKey(choice.value.toString(), choice.selected))
              }.width('100%')
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(UiTokens.SURFACE)
            .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            .borderRadius(UiTokens.CONTROL_RADIUS)
            Column({ space: 10 }) {
              Text(this.copy().previewLabel).fontSize(14).fontWeight(FontWeight.Bold)
                .fontColor(UiTokens.TEXT).width('100%')
              Stack({ alignContent: this.watermarkPosition === 'bottomLeft' ?
                Alignment.BottomStart : Alignment.BottomEnd }) {
                Stack({ alignContent: Alignment.Center }) {
                  Row()
                    .width('100%')
                    .height('100%')
                    .backgroundColor(WatermarkPreviewStyle.BACKGROUND)
                    .opacity(this.previewLayer().backgroundOpacity)
                    .borderRadius(UiTokens.CONTROL_RADIUS)
                  Column({ space: 8 }) {
                    Text(this.project?.name ?? this.copy().nameLabel).fontSize(18 * this.fontScale)
                      .fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%').maxLines(2)
                      .lineHeight(this.previewLayout().projectNameLineHeight)
                      .opacity(this.previewLayer().contentOpacity)
                    Text(tr('工程部位 · 工作内容\n拍摄人  2026-08-20 12:00',
                      'Location · Work\nPhotographer  2026-08-20 12:00'))
                      .fontSize(13 * this.fontScale).fontColor(Color.White)
                      .lineHeight(this.previewLayout().detailLineHeight)
                      .width('100%')
                      .opacity(this.previewLayer().contentOpacity)
                  }
                  .padding(16)
                  .width('100%')
                  .height('100%')
                }
                .width('88%')
                .height(this.previewLayout().panelHeight)
                .border({ width: 3, color: this.accent })
                .opacity(this.previewLayer().borderOpacity)
                .borderRadius(UiTokens.CONTROL_RADIUS)
              }
              .width('100%')
              .height(this.previewLayout().frameHeight)
              .padding(12)
              .backgroundColor(UiTokens.SURFACE_MUTED)
              .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
              .borderRadius(UiTokens.CONTROL_RADIUS)
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(UiTokens.SURFACE)
            .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            .borderRadius(UiTokens.CONTROL_RADIUS)
            if (this.message.length > 0) {
              Text(this.message).fontSize(13).fontColor(UiTokens.SUCCESS).lineHeight(19)
                .padding(12).width('100%').backgroundColor(UiTokens.SURFACE_MUTED)
                .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
                .borderRadius(UiTokens.CONTROL_RADIUS)
            }
            if (this.saveError.length > 0) {
              InlineErrorPanel({ message: this.saveError, retryLabel: tr('重试保存', 'Retry save'),
                onRetry: (): void => { this.save(); } })
            }
          }
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 12, bottom: 40 })
          .width('100%')
        }.layoutWeight(1)
        }
      }
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }
    .hideTitleBar(true)
  }
}

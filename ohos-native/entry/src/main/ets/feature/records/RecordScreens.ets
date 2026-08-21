import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppRuntime } from '../../app/AppRuntime';
import { Routes } from '../../app/Routes';
import { CaptureFilter, CapturePage, CapturePageCursor, CaptureRecord, CaptureTemplateRecord, ProjectRecord } from '../../domain/Models';
import { CAPTURE_TEMPLATE_LIMIT_PER_PROJECT, CAPTURE_TEMPLATE_NAME_MAX_LENGTH, captureTemplateNameKey,
  normalizeCaptureTemplateName, resolveWatermarkLocale } from '../../domain/DomainRules';
import { CaptureStatus, ProjectLifecycleStatus } from '../../domain/StateMachine';
import { AppSearchField, AppTopBar, BatchActionBar, BatchActionItem, EmptyPanel, FilterToolbar,
  InlineErrorPanel, ListSkeleton, SectionHeader } from '../../shared/AppComponents';
import { formatBytes, formatDateTime, imageUri, statusLabel } from '../../shared/Formatters';
import { UiTokens } from '../../shared/UiTokens';
import { CaptureCard, CaptureInfoRow } from './RecordComponents';
import { ProjectBackupService } from '../backup/BackupService';
import { tr } from '../../shared/AppText';
import { CapturePageLoader, CapturePagedController } from './CapturePagedController';
import { ListPageCoordinator } from '../../shared/ListPageCoordinator';
import { clampFirstVisibleIndex } from '../../shared/ScreenStateStore';
import { AppImage, ImageDecodePolicy } from '../../shared/AppImage';
import { MotionPolicy } from '../../shared/MotionPolicy';
import { FormField, FormTextArea } from '../../shared/FormComponents';
import { CaptureDraftSnapshot, CaptureDraftValidation, CaptureFormLifecycle, CaptureFormMetrics,
  CaptureUndoCoordinator, SingleFlightRequestCoordinator,
  applyCaptureOutcome, applyDraftSuggestion, canEditCapture, filterSuggestions,
  validateCaptureDraft, validateTemplateDraft,
  validateTemplateName } from '../capture/CaptureFormPolicy';
import { DetailMediaSwapCoordinator, RecordBatchLayoutPolicy, RecordRestorePolicy, RecordSearchCoordinator,
  RecordNavigationSeedStore, RecordRefreshGate, RecordSelectionCoordinator, RenderedRefreshTracker,
  SystemRecordTimerScheduler } from './RecordUiCoordinator';
import { ScreenLifecycleActionCoordinator } from '../../shared/ScreenActionCoordinator';
import { BackAction, BackCoordinator, RootBackDispatcher } from '../../shared/ScreenUiStabilityCoordinator';

class RuntimeRecordPageLoader implements CapturePageLoader {
  load(filter: CaptureFilter, cursor: CapturePageCursor | null, pageSize: number): Promise<CapturePage> {
    return AppRuntime.require().database.listCaptures(filter, cursor, pageSize);
  }
}
@Component
export struct AllRecordsView {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private controllerRevision: number = 0;
  @State private selectionRevision: number = 0;
  @State private searchText: string = '';
  @State private filterOpen: boolean = false;
  @State private yearText: string = '';
  @State private monthText: string = '';
  @State private dayText: string = '';
  @State private projects: ProjectRecord[] = [];
  @State private selectedProjectId: string = '';
  @State private batchBusy: boolean = false;
  @State private message: string = '';
  private readonly controller: CapturePagedController = new CapturePagedController(new RuntimeRecordPageLoader(),
    (): void => { this.controllerRevision += 1; });
  private readonly recordsScroller: Scroller = new Scroller();
  private readonly pageState: ListPageCoordinator = new ListPageCoordinator();
  private readonly searchCoordinator: RecordSearchCoordinator =
    new RecordSearchCoordinator(new SystemRecordTimerScheduler());
  private readonly selection: RecordSelectionCoordinator = new RecordSelectionCoordinator();
  private readonly refreshGate: RecordRefreshGate = new RecordRefreshGate();
  private savedFirstVisibleIndex: number = 0;
  private restoreTimer: number = -1;
  private contentGeneration: number = 0;
  private projectsGeneration: number = 0;
  private readonly batchAction: ScreenLifecycleActionCoordinator = new ScreenLifecycleActionCoordinator();
  private rootBackToken: number = -1;
  private readonly refreshListener: () => void = (): void => {
    if (this.refreshGate.shouldRefresh()) {
      this.refreshContent();
    }
  };
  private readonly memoryListener: (level: number) => void = (_level: number): void => {
    this.pageState.requestSafeReload();
  };

  aboutToAppear(): void {
    const restored = AppRuntime.require().screenState.captures();
    this.searchText = restored.filter.searchText;
    this.selectedProjectId = restored.filter.projectId;
    this.yearText = restored.filter.year > 0 ? restored.filter.year.toString() : '';
    this.monthText = restored.filter.month > 0 ? restored.filter.month.toString() : '';
    this.dayText = restored.filter.day > 0 ? restored.filter.day.toString() : '';
    this.filterOpen = restored.filterOpen;
    this.savedFirstVisibleIndex = restored.firstVisibleIndex;
    this.pageState.beginRestore();
    this.activatePage();
  }

  aboutToDisappear(): void {
    this.deactivatePage();
  }

  private activatePage(): void {
    if (!this.pageState.activate()) {
      return;
    }
    this.searchCoordinator.activate();
    this.batchAction.activate();
    this.rootBackToken = RootBackDispatcher.register((): boolean => this.handleRootBack());
    this.pageState.consumeSafeReloadRequest();
    const runtime = AppRuntime.require();
    runtime.subscribe(this.refreshListener);
    runtime.uiMemory.register(this.memoryListener);
    this.refreshContent();
  }

  private deactivatePage(): void {
    if (!this.pageState.deactivate()) {
      return;
    }
    this.saveCaptureState();
    this.searchCoordinator.deactivate();
    RootBackDispatcher.unregister(this.rootBackToken);
    this.rootBackToken = -1;
    this.batchAction.invalidate();
    this.cancelRestoreTimer();
    this.contentGeneration += 1;
    this.projectsGeneration += 1;
    this.selection.invalidatePending();
    this.controller.invalidate();
    AppRuntime.current?.unsubscribe(this.refreshListener);
    AppRuntime.current?.uiMemory.unregister(this.memoryListener);
    if (this.selection.selectionMode) {
      this.selection.exit();
      this.selectionRevision += 1;
    }
    const runtime = AppRuntime.current;
    if (runtime !== null) {
      runtime.rootSelectionMode = false;
      runtime.notifyDataChanged();
    }
  }

  private currentFilter(): CaptureFilter {
    return {
      projectId: this.selectedProjectId,
      year: Number.parseInt(this.yearText) || 0,
      month: Number.parseInt(this.monthText) || 0,
      day: Number.parseInt(this.dayText) || 0,
      searchText: this.searchText
    };
  }

  private async loadProjects(): Promise<void> {
    const generation = ++this.projectsGeneration;
    try {
      const projects = await AppRuntime.require().database.listProjectsForFilter();
      if (!this.pageState.isActive() || generation !== this.projectsGeneration) {
        return;
      }
      this.projects = projects;
    } catch (_) {
      if (this.pageState.isActive() && generation === this.projectsGeneration && this.projects.length === 0) {
        this.projects = [];
      }
    }
  }

  private scheduleSearch(): void {
    this.markFilterChanged();
    this.searchCoordinator.schedule((): void => { this.resetCaptures(); });
  }

  private refreshContent(): void {
    if (!this.pageState.isActive()) {
      return;
    }
    this.pageState.beginRestore();
    this.loadProjects();
    this.resetCaptures();
  }

  private async resetCaptures(): Promise<void> {
    if (!this.pageState.isActive()) {
      return;
    }
    const generation = ++this.contentGeneration;
    await this.controller.reset(this.currentFilter());
    if (!this.pageState.isActive() || generation !== this.contentGeneration || this.controller.failed) {
      return;
    }
    await this.loadRowsForRestore(generation);
    if (!this.pageState.isActive() || generation !== this.contentGeneration || this.controller.failed) {
      return;
    }
    this.scheduleRestore(generation);
  }

  private async retryCaptures(): Promise<void> {
    if (!this.pageState.isActive()) {
      return;
    }
    const generation = ++this.contentGeneration;
    await this.controller.retry();
    if (!this.pageState.isActive() || generation !== this.contentGeneration || this.controller.failed) {
      return;
    }
    await this.loadRowsForRestore(generation);
    if (!this.pageState.isActive() || generation !== this.contentGeneration || this.controller.failed) {
      return;
    }
    this.scheduleRestore(generation);
  }

  private async loadRowsForRestore(generation: number): Promise<void> {
    while (this.pageState.isActive() && generation === this.contentGeneration &&
      this.pageState.isRestorePending() && RecordRestorePolicy.needsMoreRows(this.savedFirstVisibleIndex,
        this.captureCount(), this.controller.hasMore, this.controller.failed)) {
      const before = this.captureCount();
      await this.controller.loadNext();
      if (this.controller.failed || this.captureCount() <= before) {
        return;
      }
    }
  }

  private cancelRestoreTimer(): void {
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
  }

  private scheduleRestore(generation: number): void {
    if (!this.pageState.isRestorePending() || this.captureCount() === 0) {
      return;
    }
    this.cancelRestoreTimer();
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (!this.pageState.isActive() || generation !== this.contentGeneration ||
        !this.pageState.isRestorePending() || this.captureCount() === 0) {
        return;
      }
      const index = clampFirstVisibleIndex(this.savedFirstVisibleIndex, this.captureCount());
      this.savedFirstVisibleIndex = index;
      this.saveCaptureState();
      this.recordsScroller.scrollToIndex(index, false, ScrollAlign.START);
      this.pageState.completeRestore();
    }, 0);
  }

  private saveCaptureState(): void {
    const runtime = AppRuntime.current;
    if (runtime === null) {
      return;
    }
    runtime.screenState.saveCaptures({
      filter: this.currentFilter(),
      filterOpen: this.filterOpen,
      firstVisibleIndex: this.savedFirstVisibleIndex,
    });
  }

  private markFilterChanged(): void {
    this.selection.resetForFilterChange();
    this.touchSelection();
    this.savedFirstVisibleIndex = 0;
    this.pageState.beginRestore();
    this.saveCaptureState();
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

  private isSelectionMode(): boolean {
    return this.selectionRevision >= 0 && this.selection.selectionMode;
  }

  private touchSelection(): void {
    this.selectionRevision += 1;
  }

  private batchFontScale(): number {
    return AppRuntime.require().context.config.fontSizeScale ?? 1;
  }

  private setSelectionMode(enabled: boolean): void {
    if (this.batchBusy) return;
    if (enabled) this.selection.enter();
    else this.selection.exit();
    this.touchSelection();
    this.refreshGate.runSuppressed((): void => {
      const runtime = AppRuntime.require();
      runtime.rootSelectionMode = enabled;
      runtime.notifyDataChanged();
    });
  }

  private exitSelectionAfterBatch(): void {
    this.selection.exit();
    this.touchSelection();
    this.refreshGate.runSuppressed((): void => {
      const runtime = AppRuntime.require();
      runtime.rootSelectionMode = false;
      runtime.notifyDataChanged();
    });
  }

  private toggle(captureId: string): void {
    if (this.batchBusy) return;
    this.selection.toggle(captureId);
    this.touchSelection();
  }

  private async toggleAll(): Promise<void> {
    if (this.batchBusy) return;
    if (this.selection.allSelected) {
      this.selection.deselectAll();
      this.touchSelection();
      return;
    }
    const actionToken = this.batchAction.begin();
    if (actionToken === null) return;
    const requestedFilter = this.currentFilter();
    const token = this.selection.beginSelectAll(requestedFilter);
    this.batchBusy = true;
    try {
      const ids = await AppRuntime.require().database.captureIds(requestedFilter);
      if (!this.pageState.isActive() || !this.batchAction.isCurrent(actionToken) ||
        !this.selection.commitSelectAll(token, this.currentFilter(), ids)) return;
      this.touchSelection();
    } catch (_) {
      if (this.pageState.isActive() && this.batchAction.isCurrent(actionToken) &&
        this.selection.isSelectAllCurrent(token, this.currentFilter())) {
        this.message = tr('无法全选当前筛选结果，请重试', 'Could not select all filtered results. Try again.');
      }
    } finally {
      this.batchAction.finish(actionToken);
      if (this.pageState.isActive() && !this.batchAction.isBusy()) this.batchBusy = false;
    }
  }

  private open(capture: CaptureRecord): void {
    this.saveCaptureState();
    const runtime = AppRuntime.require();
    const path = capture.renderedPath.length > 0 ? capture.renderedPath : capture.originalPath;
    RecordNavigationSeedStore.put(capture, path.length > 0 ? imageUri(path) : '');
    runtime.selectedCaptureId = capture.id;
    this.pathStack.pushPathByName(Routes.CAPTURE_DETAIL, null);
  }

  private async batchRepublish(): Promise<void> {
    await this.runBatch(async (id: string): Promise<void> => AppRuntime.require().republishCapture(id),
      tr('已将可用水印照片再次保存到相册', 'Available watermarked photos were saved to the gallery'));
  }

  private async batchExport(): Promise<void> {
    if (this.selection.selectedIds.length === 0) {
      this.message = tr('请先选择照片', 'Select photos first');
      return;
    }
    const actionToken = this.batchAction.begin();
    if (actionToken === null) return;
    const ids = this.selection.selectedIds.slice();
    this.batchBusy = true;
    try {
      const service = new ProjectBackupService(AppRuntime.require());
      const result = await service.exportSelection(ids, false);
      const saved = await service.saveAs(result);
      if (this.pageState.isActive() && this.batchAction.isCurrent(actionToken)) {
        this.message = saved ? tr('所选照片已导出到你选择的位置',
          'Selected photos were exported to your chosen location') :
          tr('已取消保存导出文件', 'Export save was cancelled');
      }
    } catch (error) {
      if (this.pageState.isActive() && this.batchAction.isCurrent(actionToken)) {
        this.message = (error as Error).message;
      }
    } finally {
      this.batchAction.finish(actionToken);
      if (this.pageState.isActive() && !this.batchAction.isBusy()) this.batchBusy = false;
    }
  }

  private async batchClearOriginals(): Promise<void> {
    await this.runBatch(async (id: string): Promise<void> => AppRuntime.require().clearOriginal(id),
      tr('原图清理已完成', 'Original cleanup completed'));
  }

  private async batchDelete(): Promise<void> {
    if (this.selection.selectedIds.length === 0) {
      this.message = tr('请先选择照片', 'Select photos first');
      return;
    }
    if (!this.selection.requestPermanentDelete()) {
      this.touchSelection();
      this.message = tr(`再次点击“删除”将永久删除已选 ${this.selection.selectedIds.length} 条记录`,
        `Tap “Delete” again to permanently delete ${this.selection.selectedIds.length} selected records`);
      return;
    }
    await this.runBatch(async (id: string): Promise<void> => AppRuntime.require().deleteCapture(id),
      tr('所选记录已删除', 'Selected records deleted'));
  }

  private async runBatch(action: (id: string) => Promise<void>, success: string): Promise<void> {
    const ids = this.selection.selectedIds.slice();
    if (ids.length === 0) {
      this.message = tr('请先选择照片', 'Select photos first');
      return;
    }
    const actionToken = this.batchAction.begin();
    if (actionToken === null) return;
    this.batchBusy = true;
    try {
      let succeeded = 0;
      for (const id of ids) {
        try {
          await this.refreshGate.runSuppressedAsync((): Promise<void> => action(id));
          succeeded += 1;
        } catch (_) {
        }
      }
      if (this.pageState.isActive() && this.batchAction.isCurrent(actionToken)) {
        this.message = succeeded === ids.length ? success :
        tr(`已完成 ${succeeded}/${ids.length} 项，其余记录当前不可操作`,
          `Completed ${succeeded}/${ids.length}; the remaining records are not currently available`);
        this.exitSelectionAfterBatch();
        await this.resetCaptures();
      }
    } finally {
      this.batchAction.finish(actionToken);
      if (this.pageState.isActive() && !this.batchAction.isBusy()) this.batchBusy = false;
    }
  }

  private handleRootBack(): boolean {
    if (this.pathStack.size() > 0) return false;
    const action = BackCoordinator.next({
      busy: this.batchBusy,
      selection: this.isSelectionMode(),
      confirmation: this.selection.confirmDelete,
      filter: this.filterOpen,
      search: this.searchText.length > 0,
    });
    if (action === BackAction.CONSUME) return true;
    if (action === BackAction.EXIT_SELECTION) {
      this.setSelectionMode(false);
      return true;
    }
    if (action === BackAction.CLOSE_CONFIRMATION) {
      this.selection.confirmDelete = false;
      this.touchSelection();
      return true;
    }
    if (action === BackAction.CLOSE_FILTER) {
      this.filterOpen = false;
      this.saveCaptureState();
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

  @Builder
  private batchBar() {
    Column() {
      BatchActionBar({ selectedLabel: tr(`已选 ${this.selection.selectedIds.length} 张`,
        `${this.selection.selectedIds.length} selected`),
        actionHeight: RecordBatchLayoutPolicy.actionHeight(this.batchFontScale()),
        actionLabelMaxLines: RecordBatchLayoutPolicy.actionLabelMaxLines(), actions: [
          new BatchActionItem('export', '⇩', tr('导出', 'Export'), false, this.batchBusy,
            tr('导出所选照片', 'Export selected photos')),
          new BatchActionItem('save', '▣', tr('再次保存', 'Save again'), false, this.batchBusy,
            tr('将所选水印照片再次保存到相册', 'Save selected watermarked photos to the gallery again')),
          new BatchActionItem('clear', '⌫', tr('清原图', 'Clear original'), false, this.batchBusy,
            tr('清理所选照片的原图', 'Clear originals for selected photos')),
          new BatchActionItem('delete', '×', tr('删除', 'Delete'), true, this.batchBusy,
            tr('永久删除所选照片，此操作无法撤销',
              'Permanently delete selected photos; this action cannot be undone')),
        ], onAction: (id: string): void => {
          if (id === 'export') this.batchExport();
          else if (id === 'save') this.batchRepublish();
          else if (id === 'clear') this.batchClearOriginals();
          else if (id === 'delete') this.batchDelete();
        } })
        .height(RecordBatchLayoutPolicy.barHeight(this.batchFontScale()))
    }
    .margin({ left: 16, right: 16, bottom: RecordBatchLayoutPolicy.bottomMargin() })
    .width('100%')
  }

  @Builder
  private filterPanel() {
    Column({ space: 10 }) {
      if (this.projects.length > 0) {
        Column({ space: 7 }) {
      Text(tr('项目', 'Project')).fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor(UiTokens.TEXT_SECONDARY)
            .width('100%')
          Scroll() {
            Row({ space: 7 }) {
        Button(tr('全部项目', 'All projects')).height(UiTokens.TOUCH_TARGET).fontSize(12)
                .enabled(!this.batchBusy)
                .fontColor(this.selectedProjectId.length === 0 ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
                .backgroundColor(this.selectedProjectId.length === 0 ? UiTokens.PRIMARY_CONTAINER : UiTokens.CONTROL)
                .onClick((): void => { this.selectedProjectId = ''; this.markFilterChanged(); })
              ForEach(this.projects, (project: ProjectRecord) => {
                Button(project.name).height(UiTokens.TOUCH_TARGET).fontSize(12)
                  .enabled(!this.batchBusy)
                  .fontColor(this.selectedProjectId === project.id ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
                  .backgroundColor(this.selectedProjectId === project.id ?
                    UiTokens.PRIMARY_CONTAINER : UiTokens.CONTROL)
                  .onClick((): void => { this.selectedProjectId = project.id; this.markFilterChanged(); })
              }, (project: ProjectRecord) => project.id)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }.width('100%')
      }
      Row({ space: 8 }) {
        TextInput({ text: this.yearText, placeholder: tr('年', 'Year') }).layoutWeight(1)
          .height(UiTokens.TOUCH_TARGET)
          .enabled(!this.batchBusy)
          .type(InputType.Number)
          .onChange((value: string): void => { this.yearText = value; this.markFilterChanged(); })
        TextInput({ text: this.monthText, placeholder: tr('月', 'Month') }).layoutWeight(1)
          .height(UiTokens.TOUCH_TARGET)
          .enabled(!this.batchBusy)
          .type(InputType.Number)
          .onChange((value: string): void => { this.monthText = value; this.markFilterChanged(); })
        TextInput({ text: this.dayText, placeholder: tr('日', 'Day') }).layoutWeight(1)
          .height(UiTokens.TOUCH_TARGET)
          .enabled(!this.batchBusy)
          .type(InputType.Number)
          .onChange((value: string): void => { this.dayText = value; this.markFilterChanged(); })
      }.width('100%')
      Row({ space: 8 }) {
        Button(tr('清除日期', 'Clear date')).layoutWeight(1).height(UiTokens.TOUCH_TARGET)
          .enabled(!this.batchBusy)
          .backgroundColor(UiTokens.CONTROL).fontColor(UiTokens.TEXT)
          .onClick((): void => {
            this.yearText = ''; this.monthText = ''; this.dayText = '';
            this.markFilterChanged(); this.resetCaptures();
          })
        Button(tr('应用筛选', 'Apply filters')).layoutWeight(1).height(UiTokens.TOUCH_TARGET)
          .enabled(!this.batchBusy)
          .backgroundColor(UiTokens.PRIMARY).fontColor(Color.White)
          .onClick((): void => {
            this.filterOpen = false; this.markFilterChanged(); this.resetCaptures();
          })
      }.width('100%')
    }
    .padding(14)
    .margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, bottom: 8 })
    .backgroundColor(UiTokens.GLASS_STRONG)
    .borderRadius(20)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      AppTopBar({ title: tr('全部记录', 'All records'), subtitle: tr('跨项目搜索与筛选',
        'Search and filter across projects'), actionLabel: this.isSelectionMode() ? tr('完成', 'Done') :
        tr('选择', 'Select'),
          actionEnabled: !this.batchBusy,
          actionAccessibilityText: this.isSelectionMode() ? tr('结束照片选择', 'Finish selecting photos') :
            tr('选择照片', 'Select photos'),
          onAction: (): void => this.setSelectionMode(!this.isSelectionMode()) })
        Column({ space: 8 }) {
          AppSearchField({ value: this.searchText, placeholder: tr('搜索项目、部位、内容、拍摄人或编号',
            'Search project, location, work, photographer, or number'),
            accessibilityLabel: tr('搜索全部拍摄记录', 'Search all capture records'),
            onChange: (value: string): void => { this.searchText = value; this.scheduleSearch(); } })
            .enabled(!this.batchBusy)
          Row({ space: 8 }) {
            Column() {
              FilterToolbar({ label: this.filterOpen ? tr('收起筛选', 'Hide filters') : tr('筛选', 'Filter'),
                summary: this.firstCaptureDate(), active: this.filterOpen,
                onOpen: (): void => {
                  this.filterOpen = !this.filterOpen;
                  this.saveCaptureState();
                } })
                .enabled(!this.batchBusy)
            }.layoutWeight(1)
            if (this.isSelectionMode()) {
              Button(this.selection.allSelected ? tr('取消全选', 'Deselect all') :
                tr('全选当前结果', 'Select all results'))
                .height(UiTokens.TOUCH_TARGET).fontSize(13).fontColor(UiTokens.PRIMARY)
                .backgroundColor(UiTokens.ACCENT_SURFACE)
                .enabled(!this.batchBusy).onClick((): void => { this.toggleAll(); })
            }
          }.width('100%')
        }
        .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, bottom: 8 })
        .width('100%')
        if (this.filterOpen) {
          this.filterPanel()
        }
        if (this.message.length > 0) {
          Text(this.message).fontSize(13).fontColor((this.message.startsWith('无法') ||
            this.message.startsWith('Could')) ? UiTokens.DANGER :
            UiTokens.PRIMARY).padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, bottom: 6 })
            .width('100%')
        }
        if (this.controller.loadingInitial && this.captureCount() === 0) {
          ListSkeleton({ rows: 3 })
        } else if (this.controller.failed && this.captureCount() === 0) {
          Column() {
            InlineErrorPanel({ message: tr('无法读取本机拍摄记录，请重试',
              'Local capture records could not be loaded. Try again.'), retryLabel: tr('重试', 'Retry'),
              onRetry: (): void => { this.retryCaptures(); } })
          }.padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 12 }).width('100%')
        } else if (!this.controller.loadingInitial && this.captureCount() === 0) {
        EmptyPanel({ icon: '▣', title: tr('暂无拍摄记录', 'No capture records'),
          message: tr('在进行中的项目里完成拍摄后，记录会显示在这里。',
            'Records appear here after you capture photos in an active project.') })
        } else {
          List({ space: 12, scroller: this.recordsScroller }) {
            LazyForEach(this.controller.data, (capture: CaptureRecord) => {
              ListItem() {
                CaptureCard({ capture: capture, selectionMode: this.isSelectionMode(),
                  selected: this.selection.selectedIds.indexOf(capture.id) >= 0, showProject: true,
                  onOpen: (): void => this.open(capture), onToggle: (): void => this.toggle(capture.id) })
              }
            }, (capture: CaptureRecord): string => capture.id)
            if (this.controller.loadingInitial || this.controller.loadingMore) {
              ListItem() { LoadingProgress().width(30).height(30).color(UiTokens.PRIMARY) }
            }
            if (this.controller.failed) {
              ListItem() {
                InlineErrorPanel({ message: tr('记录加载失败，已保留现有内容',
                  'Records could not be loaded. Existing records were kept.'), retryLabel: tr('重试', 'Retry'),
                  onRetry: (): void => { this.retryCaptures(); } })
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING,
            top: 4, bottom: RecordBatchLayoutPolicy.listBottomPadding(this.isSelectionMode(),
              this.batchFontScale()) })
          .cachedCount(4)
          .edgeEffect(EdgeEffect.Spring)
          .onScrollIndex((start: number, _end: number): void => {
            if (!this.pageState.canSaveScroll()) return;
            this.savedFirstVisibleIndex = Math.max(0, start);
            this.saveCaptureState();
          })
          .onReachEnd((): void => { this.controller.loadNext(); })
        }
      }
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
      if (this.isSelectionMode()) {
        this.batchBar()
      }
    }
    .width('100%').height('100%')
  }
}

@Component
export struct CaptureFormScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private project: ProjectRecord | null = null;
  @State private workLocation: string = '';
  @State private workContent: string = '';
  @State private photographer: string = '';
  @State private notes: string = '';
  @State private locationSuggestions: string[] = [];
  @State private contentSuggestions: string[] = [];
  @State private photographerSuggestions: string[] = [];
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private locationGranted: boolean = false;
  @State private locationPromptDismissed: boolean = false;
  @State private templates: CaptureTemplateRecord[] = [];
  @State private templateOpen: boolean = false;
  @State private templateName: string = '';
  @State private renamingTemplateId: string = '';
  @State private deleteTemplateId: string = '';
  @State private watermarkLocaleCode: string = 'zh';
  @State private locationError: string = '';
  @State private contentError: string = '';
  @State private photographerError: string = '';
  @State private notesError: string = '';
  @State private suggestionField: string = '';
  @State private focusedField: string = '';
  @State private suggestionFilter: string = '';
  @State private undoAvailable: boolean = false;
  @State private loadFailed: boolean = false;
  @State private templateLoadFailed: boolean = false;
  @State private templateNameError: string = '';
  private readonly undo: CaptureUndoCoordinator = new CaptureUndoCoordinator();
  private readonly lifecycle: CaptureFormLifecycle = new CaptureFormLifecycle();
  private readonly loadRequest: SingleFlightRequestCoordinator = new SingleFlightRequestCoordinator();
  private readonly templateRequest: SingleFlightRequestCoordinator = new SingleFlightRequestCoordinator();
  private captureGeneration: number = 0;

  aboutToAppear(): void {
    this.lifecycle.activate();
    this.load();
  }

  aboutToDisappear(): void {
    this.lifecycle.deactivate();
    this.loadRequest.invalidate();
    this.templateRequest.invalidate();
  }

  private async load(): Promise<void> {
    const request = this.loadRequest.begin();
    if (request === 0) return;
    const generation = this.lifecycle.snapshot();
    const runtime = AppRuntime.require();
    try {
      const project = await runtime.database.projectById(runtime.selectedProjectId);
      if (!this.lifecycle.accept(generation) || !this.loadRequest.accept(request)) return;
      const settings = await runtime.database.settings();
      if (!this.lifecycle.accept(generation) || !this.loadRequest.accept(request)) return;
      const systemLocale = runtime.context.resourceManager.getConfigurationSync().locale;
      const locationGranted = await runtime.services.getLocationPermissionState();
      if (!this.lifecycle.accept(generation) || !this.loadRequest.accept(request)) return;
      this.project = project;
      this.watermarkLocaleCode = resolveWatermarkLocale(settings.localeCode, systemLocale);
      this.locationGranted = locationGranted;
      this.locationPromptDismissed = settings.locationPermissionPromptDismissed;
      this.loadFailed = project === null;
    } catch (_) {
      if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) {
        this.loadFailed = true;
        this.message = tr('项目与拍摄表单暂时无法读取，请重试',
          'The project and capture form could not be loaded. Try again.');
      }
      this.loadRequest.finish(request);
      return;
    }
    try {
      const recent = await runtime.database.listCaptures({
        projectId: runtime.selectedProjectId, year: 0, month: 0, day: 0, searchText: ''
      }, null, 1);
      if (this.lifecycle.accept(generation) && this.loadRequest.accept(request) && recent.rows.length > 0 &&
        this.workLocation.length === 0 && this.workContent.length === 0 && this.photographer.length === 0) {
        this.workLocation = recent.rows[0].workLocation;
        this.workContent = recent.rows[0].workContent;
        this.photographer = recent.rows[0].photographer;
      }
    } catch (_) {
      // Previous values are an optional convenience; manual entry remains available.
    }
    try {
      const suggestions = await runtime.database.recentSuggestions(runtime.selectedProjectId,
        'work_location', CaptureFormMetrics.ALL_SUGGESTION_COUNT);
      if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) this.locationSuggestions = suggestions;
    } catch (_) { if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) this.locationSuggestions = []; }
    try {
      const suggestions = await runtime.database.recentSuggestions(runtime.selectedProjectId,
        'work_content', CaptureFormMetrics.ALL_SUGGESTION_COUNT);
      if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) this.contentSuggestions = suggestions;
    } catch (_) { if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) this.contentSuggestions = []; }
    try {
      const suggestions = await runtime.database.recentSuggestions(runtime.selectedProjectId,
        'photographer', CaptureFormMetrics.ALL_SUGGESTION_COUNT);
      if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) this.photographerSuggestions = suggestions;
    } catch (_) { if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) this.photographerSuggestions = []; }
    this.loadRequest.finish(request);
    await this.reloadTemplates();
  }

  private async reloadTemplates(): Promise<void> {
    const request = this.templateRequest.begin();
    if (request === 0) return;
    const generation = this.lifecycle.snapshot();
    try {
      const templates = await AppRuntime.require().database.listTemplates(AppRuntime.require().selectedProjectId);
      if (!this.lifecycle.accept(generation) || !this.templateRequest.accept(request)) return;
      this.templates = templates;
      this.templateLoadFailed = false;
      this.message = '';
    } catch (_) {
      if (this.lifecycle.accept(generation) && this.templateRequest.accept(request)) {
        this.templateLoadFailed = true;
        this.message = tr('拍摄模板仍无法读取，请稍后再试',
          'Capture templates still could not be loaded. Try again later.');
      }
    } finally {
      this.templateRequest.finish(request);
    }
  }

  private handleBack(): void {
    if (this.suggestionField.length > 0) {
      this.suggestionField = '';
      this.suggestionFilter = '';
      this.lifecycle.closeTransient();
      return;
    }
    if (this.templateOpen || this.renamingTemplateId.length > 0 || this.deleteTemplateId.length > 0) {
      this.templateOpen = false;
      this.renamingTemplateId = '';
      this.deleteTemplateId = '';
      this.templateName = '';
      this.lifecycle.closeTransient();
      return;
    }
    this.captureGeneration += 1;
    this.pathStack.pop();
  }

  private applyValidation(validation: CaptureDraftValidation): void {
    this.locationError = validation.locationError;
    this.contentError = validation.workError;
    this.photographerError = validation.photographerError;
    this.notesError = validation.notesError;
  }

  private currentSnapshot(): CaptureDraftSnapshot {
    return new CaptureDraftSnapshot(this.workLocation, this.workContent, this.photographer, this.notes);
  }

  private focusField(field: string): void {
    this.focusedField = field;
    if (this.templateOpen) {
      this.templateOpen = false;
      this.renamingTemplateId = '';
      this.deleteTemplateId = '';
      this.templateName = '';
      this.lifecycle.closeTransient();
    }
    if (this.suggestionField.length > 0 && this.suggestionField !== field) {
      this.suggestionField = '';
      this.suggestionFilter = '';
      this.lifecycle.closeTransient();
    }
  }

  private rememberAndApply(field: string, value: string): void {
    const application = applyDraftSuggestion(this.currentSnapshot(), field, value);
    this.undo.arm(application.previous);
    this.undoAvailable = true;
    this.workLocation = application.value.location;
    this.workContent = application.value.work;
    this.photographer = application.value.photographer;
    this.notes = application.value.notes;
    this.suggestionField = '';
    this.suggestionFilter = '';
    this.lifecycle.closeTransient();
    this.applyValidation(validateCaptureDraft(this.workLocation, this.workContent, this.photographer, this.notes));
  }

  private undoLastApplication(): void {
    const restored = this.undo.consume(this.currentSnapshot());
    if (restored === null) return;
    this.workLocation = restored.location;
    this.workContent = restored.work;
    this.photographer = restored.photographer;
    this.notes = restored.notes;
    this.undoAvailable = false;
    this.message = tr('已撤销上一次应用', 'The last application was undone');
  }

  private async dismissLocationPrompt(): Promise<void> {
    const generation = this.lifecycle.snapshot();
    const runtime = AppRuntime.require();
    try {
      const settings = await runtime.database.settings();
      settings.locationPermissionPromptDismissed = true;
      await runtime.database.updateSettings(settings);
      if (this.lifecycle.accept(generation)) this.locationPromptDismissed = true;
    } catch (_) {
      if (this.lifecycle.accept(generation)) this.message = tr('暂时无法保存位置提示设置，请稍后重试',
        'The location prompt setting could not be saved. Try again later.');
    }
  }

  private async enableLocation(): Promise<void> {
    const generation = this.lifecycle.snapshot();
    const runtime = AppRuntime.require();
    try {
      const granted = await runtime.services.requestLocationPermission();
      if (!this.lifecycle.accept(generation)) return;
      this.locationGranted = granted;
      if (!granted) {
        const settings = await runtime.database.settings();
        settings.locationPermissionPromptDismissed = true;
        await runtime.database.updateSettings(settings);
        if (!this.lifecycle.accept(generation)) return;
        this.locationPromptDismissed = true;
        this.message = tr('未授予位置权限，仍可正常拍摄；以后可在设置中重新开启',
          'Location permission was not granted. You can keep shooting and enable it later in Settings.');
      }
    } catch (_) {
      if (this.lifecycle.accept(generation)) this.message = tr('暂时无法请求位置权限，仍可继续拍摄',
        'Location permission could not be requested. You can still capture.');
    }
  }

  private applyTemplate(template: CaptureTemplateRecord): void {
    this.undo.arm(this.currentSnapshot());
    this.undoAvailable = true;
    this.workLocation = template.workLocation.trim();
    this.workContent = template.workContent.trim();
    this.photographer = template.photographer.trim();
    this.templateOpen = false;
    this.lifecycle.closeTransient();
    this.applyValidation(validateCaptureDraft(this.workLocation, this.workContent, this.photographer, this.notes));
    this.message = tr(`已应用模板“${template.name}”`, `Template “${template.name}” applied`);
  }

  private beginRename(template: CaptureTemplateRecord): void {
    this.renamingTemplateId = template.id;
    this.templateName = template.name;
    this.deleteTemplateId = '';
    this.templateNameError = '';
  }

  private requiredFieldEdited(): void {
    this.undo.requiredFieldEdited();
    this.undoAvailable = false;
  }

  private async saveTemplate(): Promise<void> {
    if (!this.lifecycle.beginSave()) return;
    const generation = this.lifecycle.snapshot();
    const nameValidation = validateTemplateName(this.templateName);
    if (!nameValidation.valid) {
      this.templateNameError = nameValidation.error;
      this.lifecycle.finishSave(generation);
      return;
    }
    const validation = validateTemplateDraft(this.templateName, this.workLocation, this.workContent,
      this.photographer);
    if (this.renamingTemplateId.length === 0 && !validation.valid) {
      this.locationError = validation.locationError;
      this.contentError = validation.workError;
      this.photographerError = validation.photographerError;
      this.templateNameError = validation.nameError;
      this.message = validation.nameError.length > 0 ? '' :
        tr('请先修正表单中的必填信息', 'Fix the required form fields first');
      this.lifecycle.finishSave(generation);
      return;
    }
    const name = normalizeCaptureTemplateName(nameValidation.value);
    const runtime = AppRuntime.require();
    try {
      if (this.renamingTemplateId.length > 0) {
        await runtime.database.renameTemplate(this.renamingTemplateId, name, captureTemplateNameKey(name));
      } else {
        if (this.templates.length >= CAPTURE_TEMPLATE_LIMIT_PER_PROJECT) {
          this.message = tr('每个项目最多保存 100 个拍摄模板', 'Each project can store up to 100 capture templates');
          return;
        }
        const now = Date.now();
        await runtime.database.saveTemplate(new CaptureTemplateRecord({
          id: util.generateRandomUUID(), projectId: runtime.selectedProjectId,
          name: name, nameKey: captureTemplateNameKey(name),
          workLocation: validation.location, workContent: validation.work,
          photographer: validation.photographer, createdAt: now, updatedAt: now
        }));
      }
      const templates = await runtime.database.listTemplates(runtime.selectedProjectId);
      if (!this.lifecycle.accept(generation)) return;
      this.templates = templates;
      this.templateName = '';
      this.templateNameError = '';
      this.renamingTemplateId = '';
      this.message = tr('拍摄模板已保存', 'Capture template saved');
    } catch (error) {
      if (this.lifecycle.accept(generation)) {
        const text = (error as Error).message.toLowerCase();
        if (text.includes('unique') || text.includes('constraint')) {
          this.templateNameError = tr('已有同名模板，请换一个名称', 'A template with this name already exists');
        } else {
          this.message = tr('模板暂时无法保存，请稍后重试',
            'The template could not be saved. Try again later.');
        }
      }
    } finally {
      this.lifecycle.finishSave(generation);
    }
  }

  private async deleteTemplate(template: CaptureTemplateRecord): Promise<void> {
    if (this.deleteTemplateId !== template.id) {
      this.deleteTemplateId = template.id;
      this.message = tr(`再次点击“确认删除”即可删除模板“${template.name}”`,
        `Tap “Confirm delete” again to delete template “${template.name}”`);
      return;
    }
    const generation = this.lifecycle.snapshot();
    try {
      await AppRuntime.require().database.deleteTemplate(template.id);
      const templates = await AppRuntime.require().database.listTemplates(template.projectId);
      if (!this.lifecycle.accept(generation)) return;
      this.templates = templates;
      this.deleteTemplateId = '';
      this.message = tr('拍摄模板已删除', 'Capture template deleted');
    } catch (_) {
      if (this.lifecycle.accept(generation)) this.message = tr('模板暂时无法删除，请稍后重试',
        'The template could not be deleted. Try again later.');
    }
  }

  private async capture(): Promise<void> {
    if (this.busy || this.project === null) {
      return;
    }
    const validation = validateCaptureDraft(this.workLocation, this.workContent, this.photographer, this.notes);
    this.applyValidation(validation);
    if (!validation.valid) {
      this.message = tr('请修正表单中标出的内容后再拍摄',
        'Fix the highlighted form fields before capturing');
      return;
    }
    const generation = ++this.captureGeneration;
    this.busy = true;
    this.message = tr('正在打开系统相机…', 'Opening the system camera…');
    try {
      const result = await AppRuntime.require().captureWorkflow.capture({
        projectId: this.project.id,
        projectName: this.project.name,
        workLocation: validation.location,
        workContent: validation.work,
        photographer: validation.photographer,
        notes: validation.notes,
        localeCode: this.watermarkLocaleCode
      });
      if (generation !== this.captureGeneration) return;
      if (result.captured) {
        const next = applyCaptureOutcome(this.currentSnapshot(), true);
        this.notes = next.notes;
        this.message = result.debugInjected ? tr(
          '模拟器已用测试样图完成拍摄，水印正在后台处理；完成后可从详情保存到系统相册',
          'The emulator used a test image. Its watermark is processing; save it to the system gallery from Details when complete.') :
          tr('已拍摄，水印正在后台处理；完成后可从详情保存到系统相册，可以继续拍摄下一张',
            'Captured. The watermark is processing; save it to the gallery from Details when complete. You can keep shooting.');
        AppRuntime.require().notifyDataChanged();
      } else {
        const next = applyCaptureOutcome(this.currentSnapshot(), false);
        this.workLocation = next.location;
        this.workContent = next.work;
        this.photographer = next.photographer;
        this.notes = next.notes;
        this.message = result.message.length > 0 ? result.message : tr('已取消拍摄', 'Capture cancelled');
      }
      try {
        const granted = await AppRuntime.require().services.getLocationPermissionState();
        if (generation === this.captureGeneration) this.locationGranted = granted;
      } catch (_) {
        // Permission refresh is informational and must not turn a completed capture into a failure.
      }
    } catch (error) {
      if (generation === this.captureGeneration) {
        const text = (error as Error).message;
        this.message = text === 'capture_form_invalid' ? tr('请修正表单中标出的内容后再拍摄',
          'Fix the highlighted form fields before capturing') :
          tr('无法完成拍摄，请检查项目状态后重试',
            'Capture could not be completed. Check the project status and try again.');
      }
    } finally {
      if (generation === this.captureGeneration) this.busy = false;
    }
  }

  @Builder
  private suggestionStrip(field: string, values: string[]) {
    if (this.focusedField === field && values.length > 0) {
      Scroll() {
        Row({ space: 7 }) {
          ForEach(filterSuggestions(values, '', CaptureFormMetrics.FOCUSED_SUGGESTION_COUNT),
            (value: string) => {
              Button(value)
                .height(CaptureFormMetrics.TOUCH_TARGET)
                .fontSize(12).fontColor(UiTokens.PRIMARY)
                .backgroundColor(UiTokens.ACCENT_SURFACE).borderRadius(22)
                .accessibilityText(tr(`应用建议 ${value}`, `Apply suggestion ${value}`))
                .onClick((): void => { this.rememberAndApply(field, value); })
            }, (value: string) => `${field}-${value}`)
          if (values.length > CaptureFormMetrics.FOCUSED_SUGGESTION_COUNT) {
            Button(tr('更多', 'More'))
              .height(CaptureFormMetrics.TOUCH_TARGET)
              .fontSize(12).fontColor(UiTokens.TEXT)
              .backgroundColor(UiTokens.CONTROL).borderRadius(22)
              .accessibilityText(tr('展开更多建议', 'Show more suggestions'))
              .onClick((): void => {
                this.suggestionField = field;
                this.suggestionFilter = '';
                this.lifecycle.openTransient(`suggestions-${field}`);
              })
          }
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      if (this.suggestionField === field) {
        Column({ space: 8 }) {
          TextInput({ text: this.suggestionFilter, placeholder: tr('筛选建议', 'Filter suggestions') })
            .height(CaptureFormMetrics.TOUCH_TARGET).fontSize(14)
            .backgroundColor(UiTokens.SURFACE_MUTED).borderRadius(UiTokens.CONTROL_RADIUS)
            .onChange((value: string): void => { this.suggestionFilter = value; })
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
            ForEach(filterSuggestions(values, this.suggestionFilter,
              CaptureFormMetrics.ALL_SUGGESTION_COUNT), (value: string) => {
              Button(value).height(CaptureFormMetrics.TOUCH_TARGET).fontSize(12)
                .fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.ACCENT_SURFACE).borderRadius(22)
                .margin({ right: 7, bottom: 7 })
                .accessibilityText(tr(`应用建议 ${value}`, `Apply suggestion ${value}`))
                .onClick((): void => { this.rememberAndApply(field, value); })
            }, (value: string) => `all-${field}-${value}`)
          }.width('100%')
          Button(tr('收起建议', 'Hide suggestions')).height(CaptureFormMetrics.TOUCH_TARGET)
            .fontSize(13).fontColor(UiTokens.TEXT).backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.suggestionField = '';
              this.suggestionFilter = '';
              this.lifecycle.closeTransient();
            })
        }.padding(12).width('100%').backgroundColor(UiTokens.GLASS_STRONG)
          .borderRadius(UiTokens.CONTROL_RADIUS)
      }
    }
  }

  @Builder
  private locationField() {
    Column({ space: 7 }) {
      FormField({ label: tr('工程部位', 'Location'), value: this.workLocation,
        placeholder: tr('例如：南地块 2# 楼', 'For example: South block, Building 2'), required: true,
        error: this.locationError, maxLength: CaptureFormMetrics.LOCATION_MAX_LENGTH,
        onFieldFocus: (): void => { this.focusField('location'); },
        onChange: (value: string): void => {
          this.requiredFieldEdited(); this.workLocation = value; this.locationError = '';
        } })
      this.suggestionStrip('location', this.locationSuggestions)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private contentField() {
    Column({ space: 7 }) {
      FormTextArea({ label: tr('工作内容', 'Work'), value: this.workContent,
        placeholder: tr('例如：月度巡检', 'For example: Monthly inspection'), required: true,
        error: this.contentError, maxLength: CaptureFormMetrics.WORK_MAX_LENGTH,
        onFieldFocus: (): void => { this.focusField('work'); },
        onChange: (value: string): void => {
          this.requiredFieldEdited(); this.workContent = value; this.contentError = '';
        } })
      this.suggestionStrip('work', this.contentSuggestions)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private photographerField() {
    Column({ space: 7 }) {
      FormField({ label: tr('拍摄人', 'Photographer'), value: this.photographer,
        placeholder: tr('请输入姓名', 'Enter a name'), required: true,
        error: this.photographerError, maxLength: CaptureFormMetrics.PHOTOGRAPHER_MAX_LENGTH,
        onFieldFocus: (): void => { this.focusField('photographer'); },
        onChange: (value: string): void => {
          this.requiredFieldEdited(); this.photographer = value; this.photographerError = '';
        } })
      this.suggestionStrip('photographer', this.photographerSuggestions)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private templatePanel() {
    Column({ space: 10 }) {
      if (this.templateLoadFailed) {
        InlineErrorPanel({ message: tr('拍摄模板暂时无法读取', 'Capture templates could not be loaded'),
          retryLabel: tr('重试', 'Retry'), onRetry: (): void => { this.reloadTemplates(); } })
      }
      Text(this.renamingTemplateId.length > 0 ? tr('重命名模板', 'Rename template') :
        tr('把当前三项必填信息保存为模板', 'Save the three required fields as a template'))
        .fontSize(14).fontWeight(FontWeight.Bold).width('100%')
      Column({ space: 8 }) {
        FormField({ label: tr('模板名称', 'Template name'), value: this.templateName,
          placeholder: tr('请输入模板名称', 'Enter a template name'), required: true,
          error: this.templateNameError, maxLength: CAPTURE_TEMPLATE_NAME_MAX_LENGTH,
          onChange: (value: string): void => { this.templateName = value; this.templateNameError = ''; } })
        Button() {
          Text(this.renamingTemplateId.length > 0 ? tr('保存名称', 'Save name') :
            tr('保存当前', 'Save current')).maxLines(CaptureFormMetrics.TEMPLATE_ACTION_MAX_LINES)
            .textAlign(TextAlign.Center).fontSize(12).fontColor(Color.White)
        }
          .width('100%').constraintSize({ minHeight: CaptureFormMetrics.TEMPLATE_ACTION_MIN_HEIGHT })
          .backgroundColor(UiTokens.PRIMARY).fontColor(Color.White)
          .enabled(!this.templateLoadFailed)
          .onClick((): void => { this.saveTemplate(); })
      }.width('100%')
      if (this.renamingTemplateId.length > 0) {
          Button() {
            Text(tr('取消重命名', 'Cancel rename')).maxLines(CaptureFormMetrics.TEMPLATE_ACTION_MAX_LINES)
              .textAlign(TextAlign.Center).fontSize(12).fontColor(UiTokens.TEXT)
          }.width('100%').constraintSize({ minHeight: CaptureFormMetrics.TEMPLATE_ACTION_MIN_HEIGHT })
            .backgroundColor(UiTokens.CONTROL).fontColor(UiTokens.TEXT)
          .onClick((): void => {
            this.renamingTemplateId = ''; this.templateName = ''; this.templateNameError = '';
          })
      }
      if (this.templates.length === 0) {
        Text(tr('暂无模板。填写三项必填信息后即可保存。',
          'No templates yet. Complete the three required fields to save one.')).fontSize(13)
          .fontColor(UiTokens.TEXT_SECONDARY).width('100%')
      } else {
        ForEach(this.templates, (template: CaptureTemplateRecord) => {
          Column({ space: 8 }) {
            Column({ space: 3 }) {
              Text(template.name).fontSize(14).fontWeight(FontWeight.Bold)
                .maxLines(CaptureFormMetrics.TEMPLATE_ACTION_MAX_LINES).width('100%')
              Text(`${template.workLocation} · ${template.workContent} · ${template.photographer}`)
                .fontSize(11).fontColor(UiTokens.TEXT_SECONDARY).maxLines(2).width('100%')
            }.width('100%').constraintSize({ minHeight: CaptureFormMetrics.TOUCH_TARGET })
              .alignItems(HorizontalAlign.Start).onClick((): void => this.applyTemplate(template))
            Button() {
              Text(tr('改名', 'Rename')).maxLines(CaptureFormMetrics.TEMPLATE_ACTION_MAX_LINES)
                .textAlign(TextAlign.Center).fontSize(11).fontColor(UiTokens.PRIMARY)
            }.width('100%').constraintSize({ minHeight: CaptureFormMetrics.TEMPLATE_ACTION_MIN_HEIGHT })
              .backgroundColor(UiTokens.ACCENT_SURFACE).fontColor(UiTokens.PRIMARY)
              .onClick((): void => this.beginRename(template))
            Button() {
              Text(this.deleteTemplateId === template.id ? tr('确认删除', 'Confirm delete') : tr('删除', 'Delete'))
                .maxLines(CaptureFormMetrics.TEMPLATE_ACTION_MAX_LINES).textAlign(TextAlign.Center).fontSize(11)
                .fontColor(UiTokens.DANGER)
            }.width('100%').constraintSize({ minHeight: CaptureFormMetrics.TEMPLATE_ACTION_MIN_HEIGHT })
              .backgroundColor(UiTokens.DANGER_CONTAINER).fontColor(UiTokens.DANGER)
              .onClick((): void => { this.deleteTemplate(template); })
          }.padding(10).width('100%').backgroundColor(Color.White).borderRadius(15)
        }, (template: CaptureTemplateRecord) => template.id)
      }
    }
    .padding(14).width('100%').backgroundColor(UiTokens.GLASS_STRONG).borderRadius(20)
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('现场拍摄', 'Site capture'), subtitle: this.project?.name ?? '', showBack: true,
          backAccessibilityText: tr('返回项目详情', 'Back to project details'),
          onBack: (): void => { this.handleBack(); } })
        Scroll() {
          Column({ space: 16 }) {
            if (!this.locationGranted && !this.locationPromptDismissed) {
              Column({ space: 10 }) {
              Text(tr('如需在水印中记录位置，可在拍摄前启用一次前台位置权限；不启用也可以正常拍摄。',
                'Enable foreground location before capture if you want it in the watermark. Capturing works without it.'))
                  .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(18).width('100%')
                Row({ space: 8 }) {
                  Button(tr('暂不使用', 'Not now')).layoutWeight(1)
                    .height(CaptureFormMetrics.TOUCH_TARGET).fontSize(11)
                    .fontColor(UiTokens.TEXT_SECONDARY)
                    .backgroundColor(Color.Transparent).onClick((): void => { this.dismissLocationPrompt(); })
                  Button(tr('启用位置', 'Enable location')).layoutWeight(1)
                    .height(CaptureFormMetrics.TOUCH_TARGET).fontSize(11)
                    .fontColor(UiTokens.PRIMARY)
                    .backgroundColor(Color.White).onClick((): void => { this.enableLocation(); })
                }.width('100%')
              }
              .padding(14).width('100%').backgroundColor('#EAF4EE').borderRadius(16)
            }
            Button(this.templateOpen ? tr('收起拍摄模板', 'Hide capture templates') :
              tr(`拍摄模板（${this.templates.length}）`, `Capture templates (${this.templates.length})`))
              .height(CaptureFormMetrics.TOUCH_TARGET).width('100%').fontSize(14).fontColor(UiTokens.PRIMARY)
              .backgroundColor(UiTokens.ACCENT_SURFACE).onClick((): void => {
                this.templateOpen = !this.templateOpen;
                this.focusedField = '';
                this.suggestionField = '';
                this.suggestionFilter = '';
                if (this.templateOpen) this.lifecycle.openTransient('templates');
                else this.lifecycle.closeTransient();
              })
            if (this.templateOpen) {
              this.templatePanel()
            }
            this.locationField()
            this.contentField()
            this.photographerField()
            FormTextArea({ label: tr('备注（选填）', 'Notes (optional)'), value: this.notes,
              placeholder: tr('仅用于此张记录，连续拍摄后会自动清空',
                'Applies only to this record and clears after each capture'),
              error: this.notesError, maxLength: CaptureFormMetrics.NOTES_MAX_LENGTH,
              onFieldFocus: (): void => { this.focusField(''); },
              onChange: (value: string): void => { this.notes = value; this.notesError = ''; } })
            if (this.undoAvailable) {
              Button(tr('撤销上一次应用', 'Undo last application'))
                .height(CaptureFormMetrics.TOUCH_TARGET).fontSize(13).fontColor(UiTokens.PRIMARY)
                .backgroundColor(UiTokens.CONTROL).accessibilityText(tr('撤销上一次模板或建议应用',
                  'Undo the last template or suggestion application'))
                .onClick((): void => { this.undoLastApplication(); })
            }
            if (this.loadFailed) {
              InlineErrorPanel({ message: tr('项目或表单数据暂时无法读取',
                'Project or form data could not be loaded'), retryLabel: tr('重试', 'Retry'),
                onRetry: (): void => { this.load(); } })
            }
            if (this.message.length > 0) {
              Text(this.message).fontSize(13)
              .fontColor((this.message.includes('无法') || this.message.toLowerCase().includes('could not')) ?
                UiTokens.DANGER : UiTokens.PRIMARY)
                .lineHeight(19).width('100%')
            }
            Button(this.busy ? tr('正在打开系统相机…', 'Opening the system camera…') : tr('拍摄', 'Capture'))
              .height(56).fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .backgroundColor(UiTokens.PRIMARY).borderRadius(28).width('100%')
              .enabled(!this.busy && this.project?.lifecycleStatus === ProjectLifecycleStatus.ACTIVE)
              .onClick((): void => { this.capture(); })
            Text(tr('拍照由系统相机完成。返回后水印在后台串行处理，工程部位、工作内容和拍摄人会保留。',
              'The system camera takes the photo. Watermarks process serially after you return; location, work, and photographer are retained.'))
              .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(18).width('100%')
          }
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 10, bottom: 40 })
          .width('100%')
        }.layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }
    .hideTitleBar(true)
    .onBackPressed((): boolean => {
      this.handleBack();
      return true;
    })
  }
}

@Component
export struct CaptureDetailScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private capture: CaptureRecord | null = null;
  @State private project: ProjectRecord | null = null;
  @State private loadingRecord: boolean = true;
  @State private showingOriginal: boolean = false;
  @State private fileSize: number = 0;
  @State private message: string = '';
  @State private confirmDelete: boolean = false;
  @State private mediaRevision: number = 0;
  private readonly pageState: ListPageCoordinator = new ListPageCoordinator();
  private readonly media: DetailMediaSwapCoordinator = new DetailMediaSwapCoordinator();
  private readonly renderedRefresh: RenderedRefreshTracker = new RenderedRefreshTracker();
  private loadGeneration: number = 0;
  private inspectionGeneration: number = 0;
  private readonly refreshListener: () => void = (): void => { this.loadRecord(); };
  private readonly memoryListener: (level: number) => void = (_level: number): void => {
    this.media.invalidate();
    this.mediaRevision += 1;
  };
  private readonly mediaSlotLoadedHandler = (generation: number, _auxiliaryGeneration: number,
    _slot: string, uri: string): void => {
    if (this.pageState.isActive()) {
      this.mediaPendingLoaded(generation, uri);
    }
  };
  private readonly mediaSlotFailedHandler = (generation: number, _auxiliaryGeneration: number,
    _slot: string, uri: string): void => {
    if (this.pageState.isActive()) {
      this.mediaPendingFailed(generation, uri);
    }
  };

  aboutToAppear(): void {
    this.applyNavigationSeed();
    this.activatePage();
  }

  aboutToDisappear(): void {
    this.deactivatePage();
  }

  private activatePage(): void {
    if (!this.pageState.activate()) {
      return;
    }
    const runtime = AppRuntime.require();
    runtime.subscribe(this.refreshListener);
    runtime.uiMemory.register(this.memoryListener);
    this.loadRecord();
  }

  private deactivatePage(): void {
    if (!this.pageState.deactivate()) {
      return;
    }
    this.loadGeneration += 1;
    this.inspectionGeneration += 1;
    this.media.invalidate();
    this.mediaRevision += 1;
    AppRuntime.current?.unsubscribe(this.refreshListener);
    AppRuntime.current?.uiMemory.unregister(this.memoryListener);
  }

  private applyNavigationSeed(): void {
    const seed = RecordNavigationSeedStore.take(AppRuntime.require().selectedCaptureId);
    if (seed === null) {
      return;
    }
    this.capture = seed.capture;
    this.loadingRecord = false;
    this.showingOriginal = false;
    this.media.initialize(seed.uri);
    this.mediaRevision += 1;
  }

  private selectedPath(capture: CaptureRecord): string {
    if (this.showingOriginal) {
      return capture.originalPath;
    }
    return capture.renderedPath.length > 0 ? capture.renderedPath : capture.originalPath;
  }

  private beginMedia(path: string, forceReload: boolean = false): void {
    const uri = path.length > 0 ? imageUri(path) : '';
    if (this.media.displayedUri.length === 0) {
      this.media.initialize(uri);
    } else {
      this.media.begin(uri, forceReload);
    }
    this.mediaRevision += 1;
  }

  private async loadRecord(): Promise<void> {
    if (!this.pageState.isActive()) {
      return;
    }
    const generation = ++this.loadGeneration;
    if (this.capture === null) {
      this.loadingRecord = true;
    }
    try {
      const capture = await AppRuntime.require().database.captureById(AppRuntime.require().selectedCaptureId);
      const project = capture === null ? null :
        await AppRuntime.require().database.projectById(capture.projectId);
      if (!this.pageState.isActive() || generation !== this.loadGeneration) {
        return;
      }
      const previous = this.capture;
      this.capture = capture;
      this.project = project;
      this.loadingRecord = false;
      if (capture === null) {
        return;
      }
      if (this.showingOriginal && !capture.hasOriginal()) {
        this.showingOriginal = false;
      }
      const path = this.selectedPath(capture);
      const becameReadyAtSamePath = previous !== null && previous.id === capture.id &&
        previous.status !== CaptureStatus.READY && capture.status === CaptureStatus.READY &&
        previous.renderedPath.length > 0 && previous.renderedPath === capture.renderedPath;
      const completedExpectedRender = !this.showingOriginal && this.renderedRefresh.consumeIfReady(
        capture.status === CaptureStatus.READY, capture.processingAttempts);
      const forceRenderedReload = !this.showingOriginal && capture.status === CaptureStatus.READY &&
        (completedExpectedRender || becameReadyAtSamePath);
      this.beginMedia(path, forceRenderedReload);
      this.inspectSelectedPath(path);
    } catch (_) {
      if (this.pageState.isActive() && generation === this.loadGeneration) {
        this.loadingRecord = false;
        this.message = tr('记录详情暂时无法读取，请重试', 'Record details could not be loaded. Try again.');
      }
    }
  }

  private async inspectSelectedPath(path: string): Promise<void> {
    const generation = ++this.inspectionGeneration;
    try {
      const inspection = await AppRuntime.require().services.inspectImage(path);
      if (!this.pageState.isActive() || generation !== this.inspectionGeneration) {
        return;
      }
      this.fileSize = inspection.exists ? inspection.sizeBytes : 0;
    } catch (_) {
      if (this.pageState.isActive() && generation === this.inspectionGeneration) {
        this.fileSize = 0;
      }
    }
  }

  private switchPhoto(original: boolean): void {
    if (original && (this.capture === null || !this.capture.hasOriginal())) {
      this.message = tr('原图已清理或不可用', 'The original was cleared or is unavailable');
      return;
    }
    this.showingOriginal = original;
    const path = this.selectedPath(this.capture!);
    const forceRenderedReload = !original && this.renderedRefresh.consumeIfReady(
      this.capture!.status === CaptureStatus.READY, this.capture!.processingAttempts);
    this.beginMedia(path, forceRenderedReload);
    this.inspectSelectedPath(path);
  }

  private mediaPendingLoaded(generation: number, uri: string): void {
    if (this.media.completePending(generation, uri)) {
      this.mediaRevision += 1;
    }
  }

  private mediaPendingFailed(generation: number, uri: string): void {
    if (this.media.failPending(generation, uri)) {
      this.mediaRevision += 1;
    }
  }

  private retryMedia(): void {
    this.media.retry();
    this.mediaRevision += 1;
  }

  private openViewer(): void {
    if (this.capture === null) {
      return;
    }
    const path = this.selectedPath(this.capture);
    const uri = this.media.displayedUri.length > 0 ? this.media.displayedUri :
      (path.length > 0 ? imageUri(path) : '');
    RecordNavigationSeedStore.put(this.capture, uri);
    AppRuntime.require().selectedCaptureId = this.capture.id;
    this.pathStack.pushPathByName(Routes.PHOTO_VIEWER, null);
  }

  private async republish(): Promise<void> {
    if (this.capture === null) return;
    try {
      await AppRuntime.require().republishCapture(this.capture.id);
      this.message = tr('已再次保存到系统相册', 'Saved to the system gallery');
    } catch (_) {
      this.message = tr('保存失败或已取消，请稍后重试', 'Save failed or was cancelled. Try again later.');
    }
  }

  private async clearOriginal(): Promise<void> {
    if (this.capture === null) return;
    try {
      await AppRuntime.require().clearOriginal(this.capture.id);
      this.showingOriginal = false;
      this.message = tr('原图已清理，水印成片和记录已保留',
        'Original cleared; the watermarked image and record were retained');
      await this.loadRecord();
    } catch (_) {
      this.message = tr('当前记录不能清理原图', 'The original cannot be cleared for this record');
    }
  }

  private async retry(): Promise<void> {
    if (this.capture === null) return;
    try {
      await AppRuntime.require().database.retryCapture(this.capture.id);
      AppRuntime.require().queue.enqueue(this.capture.id);
      AppRuntime.require().notifyDataChanged();
      this.message = tr('已重新加入后台处理队列', 'Added back to the processing queue');
    } catch (_) {
      this.message = tr('当前记录无法重新处理', 'This record cannot be reprocessed');
    }
  }

  private async deleteRecord(): Promise<void> {
    if (this.capture === null) return;
    try {
      await AppRuntime.require().deleteCapture(this.capture.id);
      this.pathStack.pop();
    } catch (_) {
      this.message = tr('处理中记录暂时不能删除', 'A processing record cannot be deleted yet');
    }
  }

  @Builder
  private mediaPane() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack() {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(UiTokens.IMAGE_PLACEHOLDER)
        if (this.mediaRevision >= 0 && this.media.slotUri('a').length > 0) {
          AppImage({ uri: this.media.slotUri('a'), requestVersion: this.media.slotVersion('a'),
            decodeEdge: ImageDecodePolicy.detail(), fit: ImageFit.Contain,
            transparentPlaceholder: this.media.isPendingSlot('a'), callbackToken: this.media.slotVersion('a'),
            callbackKey: 'a', onLoaded: this.mediaSlotLoadedHandler, onFailed: this.mediaSlotFailedHandler })
            .width('100%').height('100%')
        }
        if (this.media.slotUri('b').length > 0) {
          AppImage({ uri: this.media.slotUri('b'), requestVersion: this.media.slotVersion('b'),
            decodeEdge: ImageDecodePolicy.detail(), fit: ImageFit.Contain,
            transparentPlaceholder: this.media.isPendingSlot('b'), callbackToken: this.media.slotVersion('b'),
            callbackKey: 'b', onLoaded: this.mediaSlotLoadedHandler, onFailed: this.mediaSlotFailedHandler })
            .width('100%').height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .borderRadius(UiTokens.CARD_RADIUS)
      .sharedTransition(`capture-photo-${this.capture?.id ?? ''}`,
        { duration: MotionPolicy.duration(260), curve: Curve.Friction })
      .accessibilityText(this.capture === null ? tr('照片', 'Photo') :
        tr(`照片 ${this.capture!.photoNumber}`, `Photo ${this.capture!.photoNumber}`))
      .onClick((): void => { this.openViewer(); })
      if (this.media.failed) {
        Button(`↻  ${tr('重新加载图片', 'Reload image')}`)
          .height(UiTokens.TOUCH_TARGET)
          .fontSize(13)
          .fontColor(UiTokens.TEXT)
          .backgroundColor(UiTokens.GLASS_STRONG)
          .backdropBlur(MotionPolicy.blur(12))
          .borderRadius(UiTokens.CONTROL_RADIUS)
          .margin({ right: 10, top: 10 })
          .align(Alignment.TopEnd)
          .accessibilityText(tr('重新加载所选照片', 'Reload the selected photo'))
          .onClick((): void => { this.retryMedia(); })
      }
      Row({ space: 6 }) {
        Button(tr('水印成片', 'Watermarked')).height(UiTokens.TOUCH_TARGET).fontSize(12)
          .backgroundColor(!this.showingOriginal ? UiTokens.PRIMARY : UiTokens.GLASS_STRONG)
          .fontColor(!this.showingOriginal ? Color.White : UiTokens.TEXT)
          .accessibilityText(tr('查看水印成片', 'View watermarked photo'))
          .onClick((): void => this.switchPhoto(false))
        Button(tr('原图', 'Original')).height(UiTokens.TOUCH_TARGET).fontSize(12)
          .backgroundColor(this.showingOriginal ? UiTokens.PRIMARY : UiTokens.GLASS_STRONG)
          .fontColor(this.showingOriginal ? Color.White : UiTokens.TEXT)
          .enabled(this.capture?.hasOriginal() ?? false)
          .accessibilityText(tr('查看原图', 'View original photo'))
          .onClick((): void => this.switchPhoto(true))
      }.padding(10).backdropBlur(MotionPolicy.blur(12))
    }
    .width('100%')
    .aspectRatio(4 / 3)
    .clip(true)
    .borderRadius(UiTokens.CARD_RADIUS)
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('记录详情', 'Record details'), showBack: true,
          backAccessibilityText: tr('返回全部记录', 'Back to all records'),
          onBack: (): void => { this.pathStack.pop(); },
          actionLabel: this.capture !== null && this.project !== null &&
            canEditCapture(this.project!.lifecycleStatus, this.capture!.status,
              this.capture!.hasOriginal()) ? tr('编辑', 'Edit') : '',
          onAction: (): void => {
            if (this.capture !== null && this.project !== null &&
              canEditCapture(this.project!.lifecycleStatus, this.capture!.status,
                this.capture!.hasOriginal())) {
              this.renderedRefresh.expectNextAttempt(this.capture!.processingAttempts);
              this.pathStack.pushPathByName(Routes.CAPTURE_EDITOR, null);
            }
          } })
        if (this.capture !== null) {
          Scroll() {
            Column({ space: 14 }) {
              this.mediaPane()
              Column({ space: 11 }) {
                Row() {
                  Text(this.capture!.photoNumber).fontSize(18).fontWeight(FontWeight.Bold)
                    .layoutWeight(1).maxLines(2)
                  Text(statusLabel(this.capture!.status)).fontSize(13)
                    .fontColor(this.capture!.status === CaptureStatus.FAILED ? UiTokens.DANGER : UiTokens.SUCCESS)
                }.width('100%')
                CaptureInfoRow({ label: tr('项目', 'Project'), value: this.capture!.projectName })
                CaptureInfoRow({ label: tr('工程部位', 'Location'), value: this.capture!.workLocation })
                CaptureInfoRow({ label: tr('工作内容', 'Work'), value: this.capture!.workContent })
                CaptureInfoRow({ label: tr('拍摄人', 'Photographer'), value: this.capture!.photographer })
                CaptureInfoRow({ label: tr('拍摄时间', 'Captured at'),
                  value: formatDateTime(this.capture!.capturedAt) })
                CaptureInfoRow({ label: tr('位置', 'Position'),
                  value: this.capture!.address.length > 0 ? this.capture!.address :
                    (this.capture!.latitude === null ? tr('未记录', 'Not recorded') :
                      `${this.capture!.latitude}, ${this.capture!.longitude}`) })
                CaptureInfoRow({ label: tr('备注', 'Notes'), value: this.capture!.notes })
                CaptureInfoRow({ label: tr('文件大小', 'File size'),
                  value: this.fileSize > 0 ? formatBytes(this.fileSize) : tr('文件不可用', 'File unavailable') })
                CaptureInfoRow({ label: tr('原图', 'Original'), value: this.capture!.hasOriginal() ?
                  tr('已保留', 'Retained') : tr('已清理', 'Cleared') })
                CaptureInfoRow({ label: tr('系统相册', 'System gallery'),
                  value: this.capture!.publishedUri.length > 0 ? tr('已保存', 'Saved') :
                    tr('尚未保存，可使用下方按钮', 'Not saved; use the button below') })
                if (this.capture!.failureReason.length > 0) {
                  CaptureInfoRow({ label: tr('失败原因', 'Failure reason'),
                    value: this.capture!.failureReason })
                }
              }
              .padding(18).width('100%').backgroundColor(UiTokens.GLASS).borderRadius(UiTokens.CARD_RADIUS)
              if (this.message.length > 0) {
                Text(this.message).fontSize(13).fontColor(UiTokens.PRIMARY).width('100%')
              }
              Row({ space: 8 }) {
                if (this.capture!.status === CaptureStatus.READY) {
                  Button() {
                    Text(this.capture!.publishedUri.length > 0 ? tr('再次保存', 'Save again') :
                      tr('保存到相册', 'Save to gallery'))
                      .fontSize(13).fontColor(Color.White).maxLines(2).textAlign(TextAlign.Center)
                  }
                  .layoutWeight(1).height(UiTokens.TOUCH_TARGET)
                  .backgroundColor(UiTokens.PRIMARY).borderRadius(16)
                  .onClick((): void => { this.republish(); })
                } else if (this.capture!.status === CaptureStatus.FAILED && this.capture!.hasOriginal()) {
                  Button() {
                    Text(tr('重新处理', 'Reprocess'))
                      .fontSize(13).fontColor(Color.White).maxLines(2).textAlign(TextAlign.Center)
                  }
                  .layoutWeight(1).height(UiTokens.TOUCH_TARGET)
                  .backgroundColor(UiTokens.PRIMARY).borderRadius(16)
                  .onClick((): void => { this.retry(); })
                }
                Button() {
                  Text(tr('清理原图', 'Clear original'))
                    .fontSize(13).fontColor(UiTokens.PRIMARY).maxLines(2).textAlign(TextAlign.Center)
                }
                .layoutWeight(1).height(UiTokens.TOUCH_TARGET)
                .backgroundColor(UiTokens.CONTROL).borderRadius(16)
                .enabled(this.capture!.hasOriginal() && (this.capture!.status === CaptureStatus.READY ||
                  this.capture!.status === CaptureStatus.FAILED))
                .onClick((): void => { this.clearOriginal(); })
                Button() {
                  Text(tr('删除记录', 'Delete record'))
                    .fontSize(13).fontColor(UiTokens.DANGER).maxLines(2).textAlign(TextAlign.Center)
                }
                .layoutWeight(1).height(UiTokens.TOUCH_TARGET)
                .backgroundColor(UiTokens.DANGER_CONTAINER).borderRadius(16)
                .onClick((): void => { this.confirmDelete = !this.confirmDelete; })
              }.width('100%')
              if (this.confirmDelete) {
                Column({ space: 9 }) {
                  Text(tr('将删除应用内原图、水印成片和记录，并请求删除已发布照片。此操作无法撤销。',
                    'This deletes the private original, watermarked image, and record, and requests deletion of the published photo. This cannot be undone.'))
                    .fontSize(13).fontColor(UiTokens.DANGER).lineHeight(19).width('100%')
                  Button(tr('确认删除整条记录', 'Confirm record deletion'))
                    .height(UiTokens.TOUCH_TARGET).width('100%')
                    .backgroundColor(UiTokens.DANGER)
                    .fontColor(Color.White)
                    .accessibilityText(tr('永久删除原图、水印成片和整条记录，无法撤销',
                      'Permanently delete the original, watermarked photo, and record. This cannot be undone.'))
                    .onClick((): void => { this.deleteRecord(); })
                }.padding(14).backgroundColor(UiTokens.DELETE_PANEL).borderRadius(16).width('100%')
              }
            }
            .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 8, bottom: 40 })
            .width('100%')
          }.layoutWeight(1)
        } else if (this.loadingRecord) {
          ListSkeleton({ rows: 2 })
        } else {
          EmptyPanel({ icon: '!', title: tr('记录不存在', 'Record not found'),
            message: tr('记录可能已被删除，请返回后重试。', 'The record may have been deleted. Go back and try again.'),
            actionLabel: tr('返回', 'Back'), onAction: (): void => { this.pathStack.pop(); } })
        }
      }
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
      .onShown((): void => { this.activatePage(); })
      .onHidden((): void => { this.deactivatePage(); })
  }
}

@Component
export struct CaptureEditorScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private capture: CaptureRecord | null = null;
  @State private location: string = '';
  @State private content: string = '';
  @State private photographer: string = '';
  @State private notes: string = '';
  @State private message: string = '';
  @State private project: ProjectRecord | null = null;
  @State private locationError: string = '';
  @State private contentError: string = '';
  @State private photographerError: string = '';
  @State private notesError: string = '';
  @State private saving: boolean = false;
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  private readonly lifecycle: CaptureFormLifecycle = new CaptureFormLifecycle();
  private readonly loadRequest: SingleFlightRequestCoordinator = new SingleFlightRequestCoordinator();

  aboutToAppear(): void {
    this.lifecycle.activate();
    this.load();
  }

  aboutToDisappear(): void {
    this.lifecycle.deactivate();
    this.loadRequest.invalidate();
  }

  private async load(): Promise<void> {
    const request = this.loadRequest.begin();
    if (request === 0) return;
    const generation = this.lifecycle.snapshot();
    this.loading = true;
    this.loadFailed = false;
    this.message = '';
    try {
      const capture = await AppRuntime.require().database.captureById(AppRuntime.require().selectedCaptureId);
      if (!this.lifecycle.accept(generation) || !this.loadRequest.accept(request)) return;
      const project = capture === null ? null :
        await AppRuntime.require().database.projectById(capture.projectId);
      if (!this.lifecycle.accept(generation) || !this.loadRequest.accept(request)) return;
      this.capture = capture;
      this.project = project;
      if (capture !== null) {
        this.location = capture.workLocation;
        this.content = capture.workContent;
        this.photographer = capture.photographer;
        this.notes = capture.notes;
        if (!capture.hasOriginal()) {
          this.message = tr('原图已清理，无法重新生成水印成片',
            'The original was cleared, so the watermarked image cannot be regenerated');
        } else if (project === null || project.lifecycleStatus !== ProjectLifecycleStatus.ACTIVE) {
          this.message = tr('项目当前为只读状态，不能编辑记录',
            'This project is read-only; the record cannot be edited');
        }
      } else {
        this.message = tr('记录不存在或已被删除', 'The record does not exist or was deleted');
      }
    } catch (_) {
      if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) {
        this.loadFailed = true;
        this.message = tr('记录暂时无法读取，请在此重试',
          'The record could not be loaded. Retry here.');
      }
    } finally {
      if (this.lifecycle.accept(generation) && this.loadRequest.accept(request)) this.loading = false;
      this.loadRequest.finish(request);
    }
  }

  private editable(): boolean {
    return this.capture !== null && this.project !== null && canEditCapture(this.project!.lifecycleStatus,
      this.capture!.status, this.capture!.hasOriginal());
  }

  private applyValidation(validation: CaptureDraftValidation): void {
    this.locationError = validation.locationError;
    this.contentError = validation.workError;
    this.photographerError = validation.photographerError;
    this.notesError = validation.notesError;
  }

  private async save(): Promise<void> {
    if (!this.lifecycle.beginSave() || this.capture === null) return;
    const generation = this.lifecycle.snapshot();
    const validation = validateCaptureDraft(this.location, this.content, this.photographer, this.notes);
    this.applyValidation(validation);
    if (!validation.valid) {
      this.message = tr('请修正表单中标出的内容后再保存',
        'Fix the highlighted form fields before saving');
      this.lifecycle.finishSave(generation);
      return;
    }
    this.saving = true;
    try {
      const project = await AppRuntime.require().database.projectById(this.capture.projectId);
      if (!this.lifecycle.accept(generation)) return;
      const current = await AppRuntime.require().database.captureById(this.capture.id);
      if (!this.lifecycle.accept(generation)) return;
      if (project === null || current === null ||
        !canEditCapture(project.lifecycleStatus, current.status, current.hasOriginal())) {
        this.message = current !== null && !current.hasOriginal() ?
          tr('原图已清理，无法保存并重新处理',
            'The original was cleared, so this edit cannot be saved and reprocessed') :
          tr('项目或记录状态已变化，请返回后重新打开',
            'The project or record changed. Go back and open it again.');
        return;
      }
      await AppRuntime.require().database.updateCaptureFields(current.id, validation.location,
        validation.work, validation.photographer, validation.notes);
      AppRuntime.require().queue.enqueue(this.capture.id);
      AppRuntime.require().notifyDataChanged();
      if (this.lifecycle.accept(generation)) this.pathStack.pop();
    } catch (_) {
      if (this.lifecycle.accept(generation)) this.message = tr('记录状态已变化，请返回后重新打开',
        'The record changed. Go back and open it again.');
    } finally {
      if (this.lifecycle.accept(generation)) this.saving = false;
      this.lifecycle.finishSave(generation);
    }
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('编辑记录', 'Edit record'), showBack: true,
          backAccessibilityText: tr('取消编辑并返回记录详情',
            'Cancel editing and return to record details'),
          onBack: (): void => { this.pathStack.pop(); },
          actionLabel: this.editable() ? (this.saving ? tr('保存中…', 'Saving…') : tr('保存', 'Save')) : '',
          actionAccessibilityText: tr('保存编辑并重新生成水印成片',
            'Save edits and regenerate the watermarked image'),
          onAction: (): void => { this.save(); } })
        if (this.loading) {
          ListSkeleton({ rows: 3 })
        } else if (this.loadFailed) {
          InlineErrorPanel({ message: this.message, retryLabel: tr('原地重试', 'Retry'),
            onRetry: (): void => { this.load(); } })
        } else {
          Scroll() {
            Column({ space: 14 }) {
            FormField({ label: tr('工程部位', 'Location'), value: this.location, required: true,
              error: this.locationError, maxLength: CaptureFormMetrics.LOCATION_MAX_LENGTH,
              fieldEnabled: this.editable(),
              onChange: (value: string): void => { this.location = value; this.locationError = ''; } })
            FormTextArea({ label: tr('工作内容', 'Work'), value: this.content, required: true,
              error: this.contentError, maxLength: CaptureFormMetrics.WORK_MAX_LENGTH,
              fieldEnabled: this.editable(),
              onChange: (value: string): void => { this.content = value; this.contentError = ''; } })
            FormField({ label: tr('拍摄人', 'Photographer'), value: this.photographer, required: true,
              error: this.photographerError, maxLength: CaptureFormMetrics.PHOTOGRAPHER_MAX_LENGTH,
              fieldEnabled: this.editable(),
              onChange: (value: string): void => {
                this.photographer = value; this.photographerError = '';
              } })
            FormTextArea({ label: tr('备注（选填）', 'Notes (optional)'), value: this.notes,
              error: this.notesError, maxLength: CaptureFormMetrics.NOTES_MAX_LENGTH,
              fieldEnabled: this.editable(),
              onChange: (value: string): void => { this.notes = value; this.notesError = ''; } })
            Text(tr('保存后会用当前项目水印设置重新生成成片；原照片编号和拍摄时间保持不变。',
              'Saving regenerates the image with current project watermark settings. The photo number and capture time stay unchanged.'))
              .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(20).width('100%')
            if (this.message.length > 0) {
              Text(this.message).fontSize(13).fontColor(UiTokens.DANGER).width('100%')
            }
            }
            .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 12, bottom: 40 })
            .width('100%')
          }.layoutWeight(1)
        }
      }
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
      .onBackPressed((): boolean => {
        this.pathStack.pop();
        return true;
      })
  }
}

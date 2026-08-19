import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppRuntime } from '../../app/AppRuntime';
import { Routes } from '../../app/Routes';
import { CaptureFilter, CapturePage, CapturePageCursor, CaptureRecord, CaptureTemplateRecord, ProjectRecord } from '../../domain/Models';
import { CAPTURE_TEMPLATE_CONTENT_MAX_LENGTH, CAPTURE_TEMPLATE_LIMIT_PER_PROJECT,
  CAPTURE_TEMPLATE_LOCATION_MAX_LENGTH, CAPTURE_TEMPLATE_NAME_MAX_LENGTH,
  CAPTURE_TEMPLATE_PHOTOGRAPHER_MAX_LENGTH, captureTemplateNameKey,
  normalizeCaptureTemplateName, resolveWatermarkLocale, validateTemplateField } from '../../domain/DomainRules';
import { CaptureStatus, ProjectLifecycleStatus } from '../../domain/StateMachine';
import { AppTopBar, EmptyPanel, ListSkeleton, SectionHeader } from '../../shared/AppComponents';
import { formatBytes, formatDateTime, imageUri, statusLabel } from '../../shared/Formatters';
import { UiTokens } from '../../shared/UiTokens';
import { CaptureCard, CaptureInfoRow, captureCardKey } from './RecordComponents';
import { ProjectBackupService } from '../backup/BackupService';
import { tr } from '../../shared/AppText';

@Component
export struct AllRecordsView {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private captures: CaptureRecord[] = [];
  @State private cursor: CapturePageCursor | null = null;
  @State private loading: boolean = true;
  @State private loadingMore: boolean = false;
  @State private searchText: string = '';
  @State private filterOpen: boolean = false;
  @State private yearText: string = '';
  @State private monthText: string = '';
  @State private dayText: string = '';
  @State private projects: ProjectRecord[] = [];
  @State private selectedProjectId: string = '';
  @State private selectionMode: boolean = false;
  @State private selectedIds: string[] = [];
  @State private allSelected: boolean = false;
  @State private batchBusy: boolean = false;
  @State private confirmBatchDelete: boolean = false;
  @State private message: string = '';
  private searchTimer: number = -1;
  private loadGeneration: number = 0;
  private readonly refreshListener: () => void = (): void => { this.load(true); };

  aboutToAppear(): void {
    AppRuntime.require().subscribe(this.refreshListener);
    this.loadProjects();
    this.load(true);
  }

  aboutToDisappear(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.loadGeneration += 1;
    AppRuntime.require().rootSelectionMode = false;
    AppRuntime.require().notifyDataChanged();
  }

  aboutToBeDeleted(): void {
    AppRuntime.current?.unsubscribe(this.refreshListener);
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
    try {
      this.projects = await AppRuntime.require().database.listProjectsForFilter();
    } catch (_) {
      this.projects = [];
    }
  }

  private scheduleSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.load(true);
    }, 250);
  }

  private async load(reset: boolean): Promise<void> {
    if (reset) {
      this.loading = true;
      this.cursor = null;
    } else if (this.cursor === null || this.loadingMore) {
      return;
    } else {
      this.loadingMore = true;
    }
    const generation = ++this.loadGeneration;
    try {
      const page = await AppRuntime.require().database.listCaptures(this.currentFilter(),
        reset ? null : this.cursor, 50);
      if (generation !== this.loadGeneration) {
        return;
      }
      this.captures = reset ? page.rows : this.captures.concat(page.rows);
      this.cursor = page.nextCursor;
      this.message = '';
    } catch (_) {
      if (generation === this.loadGeneration) {
        this.message = tr('无法读取本机拍摄记录，请重试', 'Local capture records could not be loaded. Try again.');
      }
    } finally {
      if (generation === this.loadGeneration) {
        this.loading = false;
        this.loadingMore = false;
      }
    }
  }

  private setSelectionMode(enabled: boolean): void {
    this.selectionMode = enabled;
    if (!enabled) {
      this.selectedIds = [];
      this.allSelected = false;
      this.confirmBatchDelete = false;
    }
    AppRuntime.require().rootSelectionMode = enabled;
    AppRuntime.require().notifyDataChanged();
  }

  private toggle(captureId: string): void {
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
    if (this.batchBusy) return;
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
      this.message = tr('无法全选当前筛选结果，请重试', 'Could not select all filtered results. Try again.');
    } finally {
      this.batchBusy = false;
    }
  }

  private open(capture: CaptureRecord): void {
    AppRuntime.require().selectedCaptureId = capture.id;
    this.pathStack.pushPathByName(Routes.CAPTURE_DETAIL, null);
  }

  private async batchRepublish(): Promise<void> {
    await this.runBatch(async (id: string): Promise<void> => AppRuntime.require().republishCapture(id),
      tr('已将可用水印照片再次保存到相册', 'Available watermarked photos were saved to the gallery'));
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
    } catch (error) {
      this.message = (error as Error).message;
    }
  }

  private async batchClearOriginals(): Promise<void> {
    await this.runBatch(async (id: string): Promise<void> => AppRuntime.require().clearOriginal(id),
      tr('原图清理已完成', 'Original cleanup completed'));
  }

  private async batchDelete(): Promise<void> {
    if (!this.confirmBatchDelete) {
      this.confirmBatchDelete = true;
      this.message = tr(`再次点击“确认删除”将永久删除已选 ${this.selectedIds.length} 条记录`,
        `Tap “Confirm delete” again to permanently delete ${this.selectedIds.length} selected records`);
      return;
    }
    await this.runBatch(async (id: string): Promise<void> => AppRuntime.require().deleteCapture(id),
      tr('所选记录已删除', 'Selected records deleted'));
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
      tr(`已完成 ${succeeded}/${ids.length} 项，其余记录当前不可操作`,
        `Completed ${succeeded}/${ids.length}; the remaining records are not currently available`);
      this.setSelectionMode(false);
      await this.load(true);
    } finally {
      this.batchBusy = false;
    }
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
        Button(tr('再次保存', 'Save')).layoutWeight(1).height(42).fontSize(12)
          .backgroundColor(Color.Transparent).fontColor(UiTokens.TEXT).enabled(!this.batchBusy)
          .onClick((): void => { this.batchRepublish(); })
        Button(tr('清理原图', 'Clear originals')).layoutWeight(1).height(42).fontSize(11)
          .backgroundColor(Color.Transparent).fontColor(UiTokens.TEXT).enabled(!this.batchBusy)
          .onClick((): void => { this.batchClearOriginals(); })
        Button(this.confirmBatchDelete ? tr('确认删除', 'Confirm delete') : tr('删除所选', 'Delete'))
          .layoutWeight(1).height(42).fontSize(11)
          .fontColor(UiTokens.DANGER).backgroundColor(Color.Transparent).enabled(!this.batchBusy)
          .onClick((): void => { this.batchDelete(); })
      }.width('100%')
    }
    .padding({ left: 12, right: 12, top: 9, bottom: 10 })
    .margin({ left: 16, right: 16, bottom: 12 })
    .width('100%')
    .backgroundColor(UiTokens.GLASS_STRONG)
    .backdropBlur(24)
    .border({ width: 1, color: UiTokens.OUTLINE })
    .borderRadius(26)
    .shadow({ radius: 18, color: '#28000000', offsetY: 6 })
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
        Button(tr('全部项目', 'All projects')).height(34).fontSize(12)
                .fontColor(this.selectedProjectId.length === 0 ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
                .backgroundColor(this.selectedProjectId.length === 0 ? UiTokens.PRIMARY_CONTAINER : UiTokens.CONTROL)
                .onClick((): void => { this.selectedProjectId = ''; })
              ForEach(this.projects, (project: ProjectRecord) => {
                Button(project.name).height(34).fontSize(12)
                  .fontColor(this.selectedProjectId === project.id ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
                  .backgroundColor(this.selectedProjectId === project.id ?
                    UiTokens.PRIMARY_CONTAINER : UiTokens.CONTROL)
                  .onClick((): void => { this.selectedProjectId = project.id; })
              }, (project: ProjectRecord) => project.id)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }.width('100%')
      }
      Row({ space: 8 }) {
        TextInput({ text: this.yearText, placeholder: tr('年', 'Year') }).layoutWeight(1).height(42)
          .type(InputType.Number)
          .onChange((value: string): void => { this.yearText = value; })
        TextInput({ text: this.monthText, placeholder: tr('月', 'Month') }).layoutWeight(1).height(42)
          .type(InputType.Number)
          .onChange((value: string): void => { this.monthText = value; })
        TextInput({ text: this.dayText, placeholder: tr('日', 'Day') }).layoutWeight(1).height(42)
          .type(InputType.Number)
          .onChange((value: string): void => { this.dayText = value; })
      }.width('100%')
      Row({ space: 8 }) {
        Button(tr('清除日期', 'Clear date')).layoutWeight(1).height(38)
          .backgroundColor(UiTokens.CONTROL).fontColor(UiTokens.TEXT)
          .onClick((): void => { this.yearText = ''; this.monthText = ''; this.dayText = ''; this.load(true); })
        Button(tr('应用筛选', 'Apply filters')).layoutWeight(1).height(38)
          .backgroundColor(UiTokens.PRIMARY).fontColor(Color.White)
          .onClick((): void => { this.filterOpen = false; this.load(true); })
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
        'Search and filter across projects'), actionLabel: this.selectionMode ? tr('完成', 'Done') :
        tr('选择', 'Select'),
          onAction: (): void => this.setSelectionMode(!this.selectionMode) })
        Column({ space: 8 }) {
        TextInput({ text: this.searchText, placeholder: tr('搜索项目、部位、内容、拍摄人或编号',
          'Search project, location, work, photographer, or number') })
            .height(44).fontSize(14).backgroundColor(UiTokens.GLASS_STRONG).borderRadius(22)
            .onChange((value: string): void => { this.searchText = value; this.scheduleSearch(); })
          Row({ space: 8 }) {
          Button(this.filterOpen ? tr('收起筛选', 'Hide filters') : tr('筛选', 'Filter'))
              .height(38).fontSize(13).fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.ACCENT_SURFACE)
              .onClick((): void => { this.filterOpen = !this.filterOpen; })
            if (this.selectionMode) {
            Button(this.allSelected ? tr('取消全选', 'Deselect all') : tr('全选当前结果', 'Select all results'))
                .height(38).fontSize(13).fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.ACCENT_SURFACE)
                .enabled(!this.batchBusy).onClick((): void => { this.toggleAll(); })
            }
            Blank()
            if (this.captures.length > 0) {
              Text(formatDateTime(this.captures[0].capturedAt).substring(0, 10))
                .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY)
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
        if (this.loading && this.captures.length === 0) {
          ListSkeleton({ rows: 3 })
        } else if (!this.loading && this.captures.length === 0) {
        EmptyPanel({ icon: '▣', title: tr('暂无拍摄记录', 'No capture records'),
          message: tr('在进行中的项目里完成拍摄后，记录会显示在这里。',
            'Records appear here after you capture photos in an active project.') })
        } else {
          List({ space: 12 }) {
            ForEach(this.captures, (capture: CaptureRecord) => {
              ListItem() {
                CaptureCard({ capture: capture, selectionMode: this.selectionMode,
                  selected: this.selectedIds.indexOf(capture.id) >= 0, showProject: true,
                  onOpen: (): void => this.open(capture), onToggle: (): void => this.toggle(capture.id) })
              }
            }, (capture: CaptureRecord) => captureCardKey(capture))
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING,
            top: 4, bottom: this.selectionMode ? 132 : 112 })
          .edgeEffect(EdgeEffect.Spring)
          .onReachEnd((): void => { this.load(false); })
        }
      }
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
      if (this.selectionMode) {
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

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const runtime = AppRuntime.require();
    this.project = await runtime.database.projectById(runtime.selectedProjectId);
    const settings = await runtime.database.settings();
    const systemLocale = runtime.context.resourceManager.getConfigurationSync().locale;
    this.watermarkLocaleCode = resolveWatermarkLocale(settings.localeCode, systemLocale);
    this.locationGranted = await runtime.services.getLocationPermissionState();
    this.locationPromptDismissed = settings.locationPermissionPromptDismissed;
    this.locationSuggestions = await runtime.database.recentSuggestions(runtime.selectedProjectId,
      'work_location', 5);
    this.contentSuggestions = await runtime.database.recentSuggestions(runtime.selectedProjectId,
      'work_content', 5);
    this.photographerSuggestions = await runtime.database.recentSuggestions(runtime.selectedProjectId,
      'photographer', 5);
    const recent = await runtime.database.listCaptures({
      projectId: runtime.selectedProjectId,
      year: 0,
      month: 0,
      day: 0,
      searchText: ''
    }, null, 1);
    if (recent.rows.length > 0 && this.workLocation.length === 0 && this.workContent.length === 0 &&
      this.photographer.length === 0) {
      this.workLocation = recent.rows[0].workLocation;
      this.workContent = recent.rows[0].workContent;
      this.photographer = recent.rows[0].photographer;
    }
    this.templates = await runtime.database.listTemplates(runtime.selectedProjectId);
  }

  private async dismissLocationPrompt(): Promise<void> {
    const runtime = AppRuntime.require();
    const settings = await runtime.database.settings();
    settings.locationPermissionPromptDismissed = true;
    await runtime.database.updateSettings(settings);
    this.locationPromptDismissed = true;
  }

  private async enableLocation(): Promise<void> {
    const runtime = AppRuntime.require();
    const granted = await runtime.services.requestLocationPermission();
    this.locationGranted = granted;
    if (!granted) {
      await this.dismissLocationPrompt();
      this.message = tr('未授予位置权限，仍可正常拍摄；以后可在设置中重新开启',
        'Location permission was not granted. You can keep shooting and enable it later in Settings.');
    }
  }

  private applyTemplate(template: CaptureTemplateRecord): void {
    this.workLocation = template.workLocation;
    this.workContent = template.workContent;
    this.photographer = template.photographer;
    this.templateOpen = false;
    this.message = tr(`已应用模板“${template.name}”`, `Template “${template.name}” applied`);
  }

  private beginRename(template: CaptureTemplateRecord): void {
    this.renamingTemplateId = template.id;
    this.templateName = template.name;
    this.deleteTemplateId = '';
  }

  private async saveTemplate(): Promise<void> {
    const name = normalizeCaptureTemplateName(this.templateName);
    if (!validateTemplateField(name, CAPTURE_TEMPLATE_NAME_MAX_LENGTH)) {
      this.message = tr('请输入 1–80 个字符的模板名称', 'Enter a template name from 1 to 80 characters');
      return;
    }
    const runtime = AppRuntime.require();
    try {
      if (this.renamingTemplateId.length > 0) {
        await runtime.database.renameTemplate(this.renamingTemplateId, name, captureTemplateNameKey(name));
      } else {
        if (this.templates.length >= CAPTURE_TEMPLATE_LIMIT_PER_PROJECT) {
          this.message = tr('每个项目最多保存 100 个拍摄模板', 'Each project can store up to 100 capture templates');
          return;
        }
        if (!validateTemplateField(this.workLocation, CAPTURE_TEMPLATE_LOCATION_MAX_LENGTH) ||
          !validateTemplateField(this.workContent, CAPTURE_TEMPLATE_CONTENT_MAX_LENGTH) ||
          !validateTemplateField(this.photographer, CAPTURE_TEMPLATE_PHOTOGRAPHER_MAX_LENGTH)) {
          this.message = tr('请先完整填写工程部位、工作内容和拍摄人，再保存模板',
            'Complete the location, work, and photographer fields before saving a template');
          return;
        }
        const now = Date.now();
        await runtime.database.saveTemplate(new CaptureTemplateRecord({
          id: util.generateRandomUUID(), projectId: runtime.selectedProjectId,
          name: name, nameKey: captureTemplateNameKey(name),
          workLocation: this.workLocation.trim(), workContent: this.workContent.trim(),
          photographer: this.photographer.trim(), createdAt: now, updatedAt: now
        }));
      }
      this.templates = await runtime.database.listTemplates(runtime.selectedProjectId);
      this.templateName = '';
      this.renamingTemplateId = '';
      this.message = tr('拍摄模板已保存', 'Capture template saved');
    } catch (_) {
      this.message = tr('已有同名模板，请换一个名称', 'A template with this name already exists');
    }
  }

  private async deleteTemplate(template: CaptureTemplateRecord): Promise<void> {
    if (this.deleteTemplateId !== template.id) {
      this.deleteTemplateId = template.id;
      this.message = tr(`再次点击“确认删除”即可删除模板“${template.name}”`,
        `Tap “Confirm delete” again to delete template “${template.name}”`);
      return;
    }
    await AppRuntime.require().database.deleteTemplate(template.id);
    this.templates = await AppRuntime.require().database.listTemplates(template.projectId);
    this.deleteTemplateId = '';
    this.message = tr('拍摄模板已删除', 'Capture template deleted');
  }

  private async capture(): Promise<void> {
    if (this.busy || this.project === null) {
      return;
    }
    this.busy = true;
    this.message = tr('正在打开系统相机…', 'Opening the system camera…');
    try {
      const result = await AppRuntime.require().captureWorkflow.capture({
        projectId: this.project.id,
        projectName: this.project.name,
        workLocation: this.workLocation,
        workContent: this.workContent,
        photographer: this.photographer,
        notes: this.notes,
        localeCode: this.watermarkLocaleCode
      });
      if (result.captured) {
        this.notes = '';
        this.message = result.debugInjected ? tr(
          '模拟器已用测试样图完成拍摄，水印正在后台处理；完成后可从详情保存到系统相册',
          'The emulator used a test image. Its watermark is processing; save it to the system gallery from Details when complete.') :
          tr('已拍摄，水印正在后台处理；完成后可从详情保存到系统相册，可以继续拍摄下一张',
            'Captured. The watermark is processing; save it to the gallery from Details when complete. You can keep shooting.');
        AppRuntime.require().notifyDataChanged();
      } else {
        this.message = result.message.length > 0 ? result.message : tr('已取消拍摄', 'Capture cancelled');
      }
      this.locationGranted = await AppRuntime.require().services.getLocationPermissionState();
    } catch (error) {
      const text = (error as Error).message;
      this.message = text.includes('填写') ? tr('请填写工程部位、工作内容和拍摄人',
        'Complete the location, work, and photographer fields') :
        tr('无法完成拍摄，请检查项目状态后重试', 'Capture could not be completed. Check the project status and try again.');
    } finally {
      this.busy = false;
    }
  }

  @Builder
  private locationField() {
    Column({ space: 7 }) {
      Text(tr('工程部位 *', 'Location *'))
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(UiTokens.TEXT).width('100%')
      TextInput({ text: this.workLocation,
        placeholder: tr('例如：南地块 2# 楼', 'For example: South block, Building 2') })
        .height(50).fontSize(15).backgroundColor(UiTokens.GLASS_STRONG).borderRadius(17)
        .onChange((value: string): void => { this.workLocation = value; })
      if (this.locationSuggestions.length > 0) {
        Scroll() {
          Row({ space: 7 }) {
            ForEach(this.locationSuggestions, (value: string) => {
              Button(value).height(32).fontSize(12).fontColor(UiTokens.PRIMARY)
                .backgroundColor(UiTokens.ACCENT_SURFACE).borderRadius(16)
                .onClick((): void => { this.workLocation = value; })
            }, (value: string) => value)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private contentField() {
    Column({ space: 7 }) {
      Text(tr('工作内容 *', 'Work *'))
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(UiTokens.TEXT).width('100%')
      TextInput({ text: this.workContent,
        placeholder: tr('例如：月度巡检', 'For example: Monthly inspection') })
        .height(50).fontSize(15).backgroundColor(UiTokens.GLASS_STRONG).borderRadius(17)
        .onChange((value: string): void => { this.workContent = value; })
      if (this.contentSuggestions.length > 0) {
        Scroll() {
          Row({ space: 7 }) {
            ForEach(this.contentSuggestions, (value: string) => {
              Button(value).height(32).fontSize(12).fontColor(UiTokens.PRIMARY)
                .backgroundColor(UiTokens.ACCENT_SURFACE).borderRadius(16)
                .onClick((): void => { this.workContent = value; })
            }, (value: string) => value)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private photographerField() {
    Column({ space: 7 }) {
      Text(tr('拍摄人 *', 'Photographer *'))
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(UiTokens.TEXT).width('100%')
      TextInput({ text: this.photographer, placeholder: tr('请输入姓名', 'Enter a name') })
        .height(50).fontSize(15).backgroundColor(UiTokens.GLASS_STRONG).borderRadius(17)
        .onChange((value: string): void => { this.photographer = value; })
      if (this.photographerSuggestions.length > 0) {
        Scroll() {
          Row({ space: 7 }) {
            ForEach(this.photographerSuggestions, (value: string) => {
              Button(value).height(32).fontSize(12).fontColor(UiTokens.PRIMARY)
                .backgroundColor(UiTokens.ACCENT_SURFACE).borderRadius(16)
                .onClick((): void => { this.photographer = value; })
            }, (value: string) => value)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private templatePanel() {
    Column({ space: 10 }) {
      Text(this.renamingTemplateId.length > 0 ? tr('重命名模板', 'Rename template') :
        tr('把当前三项必填信息保存为模板', 'Save the three required fields as a template'))
        .fontSize(14).fontWeight(FontWeight.Bold).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.templateName, placeholder: tr('模板名称', 'Template name') })
          .layoutWeight(1).height(42).backgroundColor(Color.White).borderRadius(14)
          .onChange((value: string): void => { this.templateName = value; })
        Button(this.renamingTemplateId.length > 0 ? tr('保存名称', 'Save name') :
          tr('保存当前', 'Save current'))
          .height(42).fontSize(12).backgroundColor(UiTokens.PRIMARY).fontColor(Color.White)
          .onClick((): void => { this.saveTemplate(); })
      }.width('100%')
      if (this.renamingTemplateId.length > 0) {
          Button(tr('取消重命名', 'Cancel rename')).height(34).fontSize(12)
            .backgroundColor(UiTokens.CONTROL).fontColor(UiTokens.TEXT)
          .onClick((): void => { this.renamingTemplateId = ''; this.templateName = ''; })
      }
      if (this.templates.length === 0) {
        Text(tr('暂无模板。填写三项必填信息后即可保存。',
          'No templates yet. Complete the three required fields to save one.')).fontSize(13)
          .fontColor(UiTokens.TEXT_SECONDARY).width('100%')
      } else {
        ForEach(this.templates, (template: CaptureTemplateRecord) => {
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Text(template.name).fontSize(14).fontWeight(FontWeight.Bold).maxLines(1).width('100%')
              Text(`${template.workLocation} · ${template.workContent} · ${template.photographer}`)
                .fontSize(11).fontColor(UiTokens.TEXT_SECONDARY).maxLines(2).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick((): void => this.applyTemplate(template))
            Button(tr('改名', 'Rename')).height(34).fontSize(11)
              .backgroundColor(UiTokens.ACCENT_SURFACE).fontColor(UiTokens.PRIMARY)
              .onClick((): void => this.beginRename(template))
            Button(this.deleteTemplateId === template.id ? tr('确认删除', 'Confirm delete') : tr('删除', 'Delete'))
              .height(34).fontSize(11).backgroundColor(UiTokens.DANGER_CONTAINER).fontColor(UiTokens.DANGER)
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
          onBack: (): void => { this.pathStack.pop(); } })
        Scroll() {
          Column({ space: 16 }) {
            if (!this.locationGranted && !this.locationPromptDismissed) {
              Column({ space: 10 }) {
              Text(tr('如需在水印中记录位置，可在拍摄前启用一次前台位置权限；不启用也可以正常拍摄。',
                'Enable foreground location before capture if you want it in the watermark. Capturing works without it.'))
                  .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(18).width('100%')
                Row({ space: 8 }) {
                  Button(tr('暂不使用', 'Not now')).layoutWeight(1).height(34).fontSize(11)
                    .fontColor(UiTokens.TEXT_SECONDARY)
                    .backgroundColor(Color.Transparent).onClick((): void => { this.dismissLocationPrompt(); })
                  Button(tr('启用位置', 'Enable location')).layoutWeight(1).height(34).fontSize(11)
                    .fontColor(UiTokens.PRIMARY)
                    .backgroundColor(Color.White).onClick((): void => { this.enableLocation(); })
                }.width('100%')
              }
              .padding(14).width('100%').backgroundColor('#EAF4EE').borderRadius(16)
            }
            Button(this.templateOpen ? tr('收起拍摄模板', 'Hide capture templates') :
              tr(`拍摄模板（${this.templates.length}）`, `Capture templates (${this.templates.length})`))
              .height(42).width('100%').fontSize(14).fontColor(UiTokens.PRIMARY)
              .backgroundColor(UiTokens.ACCENT_SURFACE).onClick((): void => { this.templateOpen = !this.templateOpen; })
            if (this.templateOpen) {
              this.templatePanel()
            }
            this.locationField()
            this.contentField()
            this.photographerField()
            Column({ space: 7 }) {
            Text(tr('备注（选填）', 'Notes (optional)')).fontSize(14).fontWeight(FontWeight.Medium).width('100%')
            TextArea({ text: this.notes, placeholder: tr('仅用于此张记录，连续拍摄后会自动清空',
              'Applies only to this record and clears after each capture') })
                .height(92).fontSize(14).backgroundColor(UiTokens.GLASS_STRONG).borderRadius(17)
                .onChange((value: string): void => { this.notes = value; })
            }.width('100%').alignItems(HorizontalAlign.Start)
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
  }
}

@Component
export struct CaptureDetailScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private capture: CaptureRecord | null = null;
  @State private showingOriginal: boolean = false;
  @State private fileSize: number = 0;
  @State private message: string = '';
  @State private confirmDelete: boolean = false;
  private readonly refreshListener: () => void = (): void => { this.load(); };

  aboutToAppear(): void {
    AppRuntime.require().subscribe(this.refreshListener);
    this.load();
  }

  aboutToDisappear(): void {
  }

  aboutToBeDeleted(): void {
    AppRuntime.current?.unsubscribe(this.refreshListener);
  }

  private async load(): Promise<void> {
    this.capture = await AppRuntime.require().database.captureById(AppRuntime.require().selectedCaptureId);
    if (this.capture !== null) {
      const path = this.showingOriginal ? this.capture.originalPath : this.capture.renderedPath;
      const inspection = await AppRuntime.require().services.inspectImage(path);
      this.fileSize = inspection.exists ? inspection.sizeBytes : 0;
    }
  }

  private switchPhoto(original: boolean): void {
    if (original && (this.capture === null || !this.capture.hasOriginal())) {
      this.message = tr('原图已清理或不可用', 'The original was cleared or is unavailable');
      return;
    }
    this.showingOriginal = original;
    this.load();
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
      await this.load();
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

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('记录详情', 'Record details'), showBack: true,
          onBack: (): void => { this.pathStack.pop(); },
          actionLabel: this.capture !== null && (this.capture!.status === CaptureStatus.READY ||
            this.capture!.status === CaptureStatus.FAILED) ? tr('编辑', 'Edit') : '',
          onAction: (): void => {
            if (this.capture !== null && (this.capture!.status === CaptureStatus.READY ||
              this.capture!.status === CaptureStatus.FAILED)) {
              this.pathStack.pushPathByName(Routes.CAPTURE_EDITOR, null);
            }
          } })
        if (this.capture !== null) {
          Scroll() {
            Column({ space: 14 }) {
              Stack({ alignContent: Alignment.Bottom }) {
                Image(imageUri(this.showingOriginal ? this.capture!.originalPath :
                  (this.capture!.renderedPath.length > 0 ? this.capture!.renderedPath : this.capture!.originalPath)))
                  .width('100%').height(330).objectFit(ImageFit.Contain).backgroundColor('#121614')
                  .borderRadius(UiTokens.CARD_RADIUS)
                  .sharedTransition(`capture-photo-${this.capture!.id}`,
                    { duration: 260, curve: Curve.Friction })
                  .onClick((): void => { this.pathStack.pushPathByName(Routes.PHOTO_VIEWER, null); })
                Row({ space: 6 }) {
                  Button(tr('水印成片', 'Watermarked')).height(34).fontSize(12)
                    .backgroundColor(!this.showingOriginal ? UiTokens.PRIMARY : '#AA29322E')
                    .fontColor(Color.White).onClick((): void => this.switchPhoto(false))
                  Button(tr('原图', 'Original')).height(34).fontSize(12)
                    .backgroundColor(this.showingOriginal ? UiTokens.PRIMARY : '#AA29322E')
                    .fontColor(Color.White).enabled(this.capture!.hasOriginal())
                    .onClick((): void => this.switchPhoto(true))
                }.padding(10)
              }.width('100%')
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
                  Button(this.capture!.publishedUri.length > 0 ? tr('再次保存', 'Save again') :
                    tr('保存到相册', 'Save to gallery'))
                    .layoutWeight(1).height(42).fontSize(13).fontColor(Color.White)
                    .backgroundColor(UiTokens.PRIMARY).borderRadius(16)
                    .onClick((): void => { this.republish(); })
                } else if (this.capture!.status === CaptureStatus.FAILED && this.capture!.hasOriginal()) {
                  Button(tr('重新处理', 'Reprocess')).layoutWeight(1).height(42).fontSize(13)
                    .fontColor(Color.White).backgroundColor(UiTokens.PRIMARY).borderRadius(16)
                    .onClick((): void => { this.retry(); })
                }
                Button(tr('清理原图', 'Clear original')).layoutWeight(1).height(42).fontSize(13)
                  .fontColor(UiTokens.PRIMARY).backgroundColor(UiTokens.CONTROL).borderRadius(16)
                  .enabled(this.capture!.hasOriginal() && (this.capture!.status === CaptureStatus.READY ||
                    this.capture!.status === CaptureStatus.FAILED))
                  .onClick((): void => { this.clearOriginal(); })
                Button(tr('删除记录', 'Delete record')).layoutWeight(1).height(42).fontSize(13)
                  .fontColor(UiTokens.DANGER).backgroundColor(UiTokens.DANGER_CONTAINER)
                  .borderRadius(16)
                  .onClick((): void => { this.confirmDelete = !this.confirmDelete; })
              }.width('100%')
              if (this.confirmDelete) {
                Column({ space: 9 }) {
                  Text(tr('将删除应用内原图、水印成片和记录，并请求删除已发布照片。此操作无法撤销。',
                    'This deletes the private original, watermarked image, and record, and requests deletion of the published photo. This cannot be undone.'))
                    .fontSize(13).fontColor(UiTokens.DANGER).lineHeight(19).width('100%')
                  Button(tr('确认删除整条记录', 'Confirm record deletion')).height(42).width('100%')
                    .backgroundColor(UiTokens.DANGER)
                    .fontColor(Color.White).onClick((): void => { this.deleteRecord(); })
                }.padding(14).backgroundColor(UiTokens.DELETE_PANEL).borderRadius(16).width('100%')
              }
            }
            .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 8, bottom: 40 })
            .width('100%')
          }.layoutWeight(1)
        } else {
          EmptyPanel({ icon: '!', title: tr('记录不存在', 'Record not found'),
            message: tr('记录可能已被删除，请返回后重试。', 'The record may have been deleted. Go back and try again.'),
            actionLabel: tr('返回', 'Back'), onAction: (): void => { this.pathStack.pop(); } })
        }
      }
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
      .onShown((): void => { this.load(); })
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

  aboutToAppear(): void {
    AppRuntime.require().database.captureById(AppRuntime.require().selectedCaptureId)
      .then((capture: CaptureRecord | null): void => {
        this.capture = capture;
        if (capture !== null) {
          this.location = capture.workLocation;
          this.content = capture.workContent;
          this.photographer = capture.photographer;
          this.notes = capture.notes;
        }
      });
  }

  private async save(): Promise<void> {
    if (this.capture === null || this.location.trim().length === 0 || this.content.trim().length === 0 ||
      this.photographer.trim().length === 0) {
      this.message = tr('请填写工程部位、工作内容和拍摄人',
        'Complete the location, work, and photographer fields');
      return;
    }
    const project = await AppRuntime.require().database.projectById(this.capture.projectId);
    if (project === null || project.lifecycleStatus !== ProjectLifecycleStatus.ACTIVE) {
      this.message = tr('项目当前为只读状态，不能编辑记录', 'This project is read-only; the record cannot be edited');
      return;
    }
    const current = await AppRuntime.require().database.captureById(this.capture.id);
    if (current === null || (current.status !== CaptureStatus.READY && current.status !== CaptureStatus.FAILED)) {
      this.message = tr('照片仍在处理中，请完成后再编辑', 'Wait for photo processing to finish before editing');
      return;
    }
    try {
      await AppRuntime.require().database.updateCaptureFields(this.capture.id, this.location,
        this.content, this.photographer, this.notes);
      AppRuntime.require().queue.enqueue(this.capture.id);
      AppRuntime.require().notifyDataChanged();
      this.pathStack.pop();
    } catch (_) {
      this.message = tr('记录状态已变化，请返回后重新打开', 'The record changed. Go back and open it again.');
    }
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('编辑记录', 'Edit record'), showBack: true,
          onBack: (): void => { this.pathStack.pop(); }, actionLabel: tr('保存', 'Save'),
          onAction: (): void => { this.save(); } })
        Scroll() {
          Column({ space: 14 }) {
            TextInput({ text: this.location, placeholder: tr('工程部位 *', 'Location *') }).height(52).fontSize(15)
              .backgroundColor(UiTokens.GLASS_STRONG).borderRadius(17)
              .onChange((value: string): void => { this.location = value; })
            TextInput({ text: this.content, placeholder: tr('工作内容 *', 'Work *') }).height(52).fontSize(15)
              .backgroundColor(UiTokens.GLASS_STRONG).borderRadius(17)
              .onChange((value: string): void => { this.content = value; })
            TextInput({ text: this.photographer, placeholder: tr('拍摄人 *', 'Photographer *') })
              .height(52).fontSize(15)
              .backgroundColor(UiTokens.GLASS_STRONG).borderRadius(17)
              .onChange((value: string): void => { this.photographer = value; })
            TextArea({ text: this.notes, placeholder: tr('备注（选填）', 'Notes (optional)') })
              .height(110).fontSize(15)
              .backgroundColor(UiTokens.GLASS_STRONG).borderRadius(17)
              .onChange((value: string): void => { this.notes = value; })
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
      .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
  }
}

@Component
export struct PhotoViewerScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private capture: CaptureRecord | null = null;
  @State private captures: CaptureRecord[] = [];
  @State private currentIndex: number = 0;
  @State private imageScale: number = 1.0;
  @State private baseScale: number = 1.0;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const runtime = AppRuntime.require();
    const selected = await runtime.database.captureById(runtime.selectedCaptureId);
    if (selected === null) return;
    const filter: CaptureFilter = { projectId: selected.projectId, year: 0, month: 0, day: 0, searchText: '' };
    const rows: CaptureRecord[] = [];
    let cursor: CapturePageCursor | null = null;
    do {
      const page: CapturePage = await runtime.database.listCaptures(filter, cursor, 100);
      for (const row of page.rows) {
        if (row.status === CaptureStatus.READY) rows.push(row);
      }
      cursor = page.nextCursor;
    } while (cursor !== null);
    this.captures = rows;
    const index = rows.findIndex((value: CaptureRecord): boolean => value.id === selected.id);
    this.currentIndex = index >= 0 ? index : 0;
    this.capture = rows.length > 0 ? rows[this.currentIndex] : selected;
  }

  private moveTo(index: number): void {
    if (index < 0 || index >= this.captures.length) return;
    this.currentIndex = index;
    this.capture = this.captures[index];
    AppRuntime.require().selectedCaptureId = this.capture!.id;
    this.imageScale = 1;
    this.baseScale = 1;
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.captures.length > 0) {
          Swiper() {
            ForEach(this.captures, (item: CaptureRecord) => {
              Image(imageUri(item.renderedPath.length > 0 ? item.renderedPath : item.originalPath))
                .width('100%').height('100%').objectFit(ImageFit.Contain).backgroundColor(Color.Black)
                .scale({ x: item.id === this.capture?.id ? this.imageScale : 1,
                  y: item.id === this.capture?.id ? this.imageScale : 1 })
                .sharedTransition(`capture-photo-${item.id}`,
                  { duration: 260, curve: Curve.Friction })
                .gesture(PinchGesture()
                  .onActionStart((): void => { this.baseScale = this.imageScale; })
                  .onActionUpdate((event: GestureEvent): void => {
                    if (item.id === this.capture?.id) {
                      this.imageScale = Math.max(1, Math.min(5, this.baseScale * event.scale));
                    }
                  }))
                .onClick((): void => { if (this.imageScale > 1) this.imageScale = 1; })
            }, (item: CaptureRecord) => item.id)
          }
          .width('100%').height('100%').index(this.currentIndex).loop(false).indicator(false)
          .disableSwipe(this.imageScale > 1)
          .onChange((index: number): void => { this.moveTo(index); })
        } else if (this.capture !== null) {
          Image(imageUri(this.capture!.renderedPath.length > 0 ? this.capture!.renderedPath :
            this.capture!.originalPath)).width('100%').height('100%').objectFit(ImageFit.Contain)
        }
        Button('‹')
          .width(46).height(46).fontSize(32).fontColor(Color.White).backgroundColor('#66000000')
          .borderRadius(23).margin({ left: 16, top: 18 }).onClick((): void => { this.pathStack.pop(); })
        if (this.captures.length > 1) {
          Text(`${this.currentIndex + 1} / ${this.captures.length}`)
            .fontSize(13).fontColor(Color.White).backgroundColor('#66000000')
            .padding({ left: 12, right: 12, top: 7, bottom: 7 }).borderRadius(16)
            .margin({ top: 26 }).align(Alignment.Top)
        }
      }
      .width('100%').height('100%').backgroundColor(Color.Black)
    }.hideTitleBar(true)
  }
}

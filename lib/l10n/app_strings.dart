import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/domain/capture_failure.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('zh'), Locale('en')];

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  bool get _english => locale.languageCode == 'en';

  String get appName => _english ? 'SiteMark' : '工程印记';
  String get noProjects => _english ? 'No projects yet' : '还没有项目';
  String get noProjectsHint => _english
      ? 'Create an engineering project before recording the site.'
      : '先创建工程项目，再开始现场拍摄记录。';
  String get newProject => _english ? 'New project' : '新建项目';
  String get createProject => _english ? 'Create project' : '创建项目';
  String get projectName => _english ? 'Project name' : '项目名称';
  String get projectNameRequired =>
      _english ? 'Enter a project name' : '请输入项目名称';
  String get projectNameAlreadyExists =>
      _english ? 'A project with this name already exists' : '已存在同名项目';
  String get projectFileNameConflict => _english
      ? 'This name conflicts with an existing project file name'
      : '项目名称生成的文件名与已有项目重复';
  String get projectActions => _english ? 'Project actions' : '项目操作';
  String get renameProject => _english ? 'Rename project' : '重命名项目';
  String get deleteProject => _english ? 'Delete project' : '删除项目';
  String get renameProjectTitle => _english ? 'Rename this project' : '重命名此项目';
  String get renameProjectFailed => _english
      ? 'Could not rename the project. Please try again.'
      : '项目重命名失败，请稍后重试';
  String get projectNameTooLong => _english
      ? 'Project name must be 120 characters or fewer'
      : '项目名称不能超过 120 个字符';
  String get deleteProjectTitle => _english ? 'Delete this project?' : '删除此项目？';
  String deleteProjectSummary({
    required String projectName,
    required int captureCount,
    required int privateOriginalCount,
  }) => _english
      ? 'Project: $projectName\n'
            'Capture records: $captureCount\n'
            'Private originals retained: $privateOriginalCount'
      : '项目：$projectName\n'
            '拍摄记录：$captureCount 条\n'
            '保留的私有原图：$privateOriginalCount 张';
  String get deleteProjectRetentionNotice => _english
      ? 'Photos already saved in the system gallery and exported backups will remain.'
      : '系统相册中的照片和已导出备份会保留。';
  String get deleteProjectIrreversible => _english
      ? 'Project data and private files in this app cannot be recovered after deletion.'
      : '删除后，应用内的项目数据和私有文件无法恢复。';
  String get deleteProjectFailed => _english
      ? 'Could not delete the project. Please try again.'
      : '项目删除失败，请稍后重试';
  String get deleteProjectPreviewFailed => _english
      ? 'Could not load deletion details. Please try again.'
      : '无法读取删除信息，请稍后重试';
  String get projectDeleted => _english
      ? 'Project deleted. Photos in the system gallery and exported backups were retained.'
      : '项目已删除，系统相册中的照片和已导出备份已保留';
  String get projectDeletedCleanupPending => _english
      ? 'Project deleted. Photos in the system gallery and exported backups were retained. Remaining private files will be cleaned up the next time the app starts.'
      : '项目已删除，系统相册中的照片和已导出备份已保留；残留私有文件将在下次启动继续清理';
  String get projectNotFound =>
      _english ? 'Project not found or deleted' : '项目不存在或已删除';
  String get projectLoadFailed => _english
      ? 'Could not load the project. Go back and try again.'
      : '项目加载失败，请返回后重试';
  String get descriptionOptional =>
      _english ? 'Description (optional)' : '项目说明（选填）';
  String get save => _english ? 'Save' : '保存';
  String get localOnly => _english ? 'Local only' : '仅保存在本机';
  String get noAds => _english ? 'No ads · No cloud' : '无广告 · 无云端';
  String get captureRecords => _english ? 'Capture records' : '拍摄记录';
  String get noCaptures => _english ? 'No site records yet' : '暂无拍摄记录';
  String get capture => _english ? 'Capture' : '拍摄';
  String get captureFormTitle => _english ? 'Watermark content' : '水印内容';
  String get workLocation => _english ? 'Work location' : '工程部位';
  String get workContent => _english ? 'Work content' : '工作内容';
  String get photographer => _english ? 'Photographer' : '拍摄人';
  String get notesOptional => _english ? 'Notes (optional)' : '备注（选填）';
  String get requiredField => _english ? 'This field is required' : '此项为必填';
  String get recentlyUsed => _english ? 'Recently used' : '最近使用';
  String get more => _english ? 'More' : '更多';
  String get searchHistory => _english ? 'Search history' : '搜索历史';
  String get noRecentSuggestions => _english ? 'No history' : '暂无历史';
  String get suggestionsLoadFailed =>
      _english ? 'Could not load suggestions' : '加载失败';
  String get captureTemplates => _english ? 'Templates' : '模板';
  String get captureTemplateCreate => _english ? 'Save current' : '保存当前内容';
  String get captureTemplateName => _english ? 'Template name' : '模板名称';
  String get captureTemplateEmpty => _english ? 'No templates yet' : '暂无模板';
  String get captureTemplateApplied => _english ? 'Template applied' : '已应用模板';
  String get captureTemplateLoadFailed =>
      _english ? 'Could not load templates' : '模板加载失败';
  String get captureTemplateSaveFailed =>
      _english ? 'Could not save template. Try again.' : '模板保存失败，请重试。';
  String get captureTemplateRenameFailed =>
      _english ? 'Could not rename template. Try again.' : '模板重命名失败，请重试。';
  String get captureTemplateDeleteFailed =>
      _english ? 'Could not delete template. Try again.' : '模板删除失败，请重试。';
  String get captureTemplateDeleteTitle =>
      _english ? 'Delete this template?' : '删除此模板？';
  String get captureTemplateDeleteNotice => _english
      ? 'Only this template will be deleted. Photos and the current form are not affected.'
      : '只会删除此模板，不会影响照片或当前已填写的表单。';
  String get captureTemplateRename => _english ? 'Rename' : '重命名';
  String get captureTemplateEmptyName =>
      _english ? 'Enter a template name' : '请输入模板名称';
  String get captureTemplateNameTooLong =>
      _english ? 'Template name is too long' : '模板名称过长';
  String get captureTemplateEmptyWorkLocation =>
      _english ? 'Work location is required' : '工程部位不能为空';
  String get captureTemplateWorkLocationTooLong =>
      _english ? 'Work location is too long' : '工程部位过长';
  String get captureTemplateEmptyWorkContent =>
      _english ? 'Work content is required' : '工作内容不能为空';
  String get captureTemplateWorkContentTooLong =>
      _english ? 'Work content is too long' : '工作内容过长';
  String get captureTemplateEmptyPhotographer =>
      _english ? 'Photographer is required' : '拍摄人不能为空';
  String get captureTemplatePhotographerTooLong =>
      _english ? 'Photographer is too long' : '拍摄人过长';
  String get captureTemplateDuplicateName =>
      _english ? 'A template with this name already exists' : '已存在同名模板';
  String get captureTemplateLimitReached =>
      _english ? 'This project already has 100 templates' : '此项目已达到 100 个模板上限';
  String get captureTemplateInvalidCharacter => _english
      ? 'Template text cannot contain unsupported characters'
      : '模板文字包含不支持的字符';
  String get captureTemplateNotFound =>
      _english ? 'Template no longer exists' : '模板已不存在';
  String get openSystemCamera => _english ? 'Capture' : '拍摄';
  String get captureWorkflowHint => _english
      ? 'Capture will invoke the system camera. Watermarks are processed in the background. You can tap capture repeatedly; return to the project detail to view records as they finish.'
      : '拍摄将调用系统相机，水印将在后台处理。可连续点击拍摄，返回项目详情即可查看处理中的记录。';
  String get ready => _english ? 'Ready' : '已完成';
  String get failed => _english ? 'Failed' : '失败';
  String get pendingCamera => _english ? 'Waiting for camera' : '等待相机';
  String get processing => _english ? 'Processing' : '处理中';

  /// `captured` records are waiting to be picked up by the background processor;
  /// `rendering` records are actively being processed. The spec distinguishes the
  /// two so the user can tell a queued shot from one currently being rendered.
  String get waitingForProcessing => _english ? 'Waiting' : '等待处理';
  String get rendering => _english ? 'Rendering watermark' : '生成水印';
  String get captureFailed => _english ? 'Capture failed' : '拍摄失败';
  String captureFailureMessage(CaptureFailureCode code) => switch (code) {
    CaptureFailureCode.cameraUnavailable =>
      _english
          ? 'The system camera is unavailable. Check the camera app and try again.'
          : '系统相机暂不可用，请检查相机应用后重试',
    CaptureFailureCode.queueUnavailable =>
      _english
          ? 'The photo is safe. Background processing will retry automatically.'
          : '照片已安全保留，后台处理会自动重试',
    CaptureFailureCode.originalMissing =>
      _english
          ? 'The original is missing, so the watermarked photo cannot be created.'
          : '原图已缺失，无法生成水印照片',
    CaptureFailureCode.originalModified =>
      _english
          ? 'The original has changed. Processing stopped to protect the record.'
          : '原图已发生变化，为保护工程记录已停止处理',
    CaptureFailureCode.processingFailed =>
      _english
          ? 'Photo processing failed. Keep the original and try processing again.'
          : '照片处理失败，请保留原图并重新处理',
    CaptureFailureCode.unexpected =>
      _english
          ? 'The photo could not be processed. Please try again.'
          : '照片处理失败，请重试',
  };
  String get captureQueuedContinue => _english
      ? 'Photo queued for background processing. Continue shooting.'
      : '照片已加入后台处理，可继续拍摄';
  String get captureQueueDelayedContinue => _english
      ? 'Photo saved. Background processing is delayed and will retry automatically; you can continue shooting.'
      : '照片已安全保留，后台处理启动延迟并会自动重试，可继续拍摄';
  String get exportProject => _english ? 'Export project' : '导出项目';
  String get exportProjectData => _english ? 'Export project data' : '导出项目资料';
  String get includeOriginals =>
      _english ? 'Include private originals' : '包含私有原图';
  String get includeOriginalsHint => _english
      ? 'This makes the ZIP larger. Originals remain local unless included.'
      : '导出包会更大；未勾选时原图仍只保存在本机。';
  String get generateAndShare => _english ? 'Generate and share' : '生成并分享';
  String get cancel => _english ? 'Cancel' : '取消';
  String get exportFailed => _english ? 'Export failed' : '导出失败';
  String get captureDetail => _english ? 'Record details' : '记录详情';
  String get originalSha256 => _english ? 'Original SHA-256' : '原图 SHA-256';
  String get capturedAt => _english ? 'Captured at' : '拍摄时间';
  String get coordinates => _english ? 'Coordinates' : '坐标';
  String get editRecord => _english ? 'Edit record' : '编辑记录';
  String get deleteRecord => _english ? 'Delete record' : '删除记录';
  String get deleteRecordPrompt => _english
      ? 'Delete the published image, private original, and local record? This cannot be undone.'
      : '将同时删除已发布成片、私有原图和本地记录，且无法撤销。';
  String get regenerateWatermark =>
      _english ? 'Regenerate watermark' : '重新生成水印';
  String get watermarkSettings => _english ? 'Watermark settings' : '水印设置';
  String get projectWatermarkSettings =>
      _english ? 'Project watermark settings' : '此项目水印设置';
  String get watermarkSettingsHint => _english
      ? 'Use a consistent engineering template. New captures and regenerated photos use these settings.'
      : '使用统一的工程水印模板；新拍照片和重新生成的成片会采用这些设置。';
  String get watermarkPosition => _english ? 'Card position' : '水印位置';
  String get bottomLeft => _english ? 'Bottom left' : '左下';
  String get bottomRight => _english ? 'Bottom right' : '右下';
  String get watermarkOpacity => _english ? 'Card opacity' : '水印透明度';
  String get watermarkFontSize => _english ? 'Font size' : '字体大小';
  String get accentColor => _english ? 'Accent color' : '强调色';
  String get green => _english ? 'Green' : '绿色';
  String get blue => _english ? 'Blue' : '蓝色';
  String get orange => _english ? 'Orange' : '橙色';
  String get red => _english ? 'Red' : '红色';
  String get purple => _english ? 'Purple' : '紫色';
  String get teal => _english ? 'Teal' : '青色';
  String get pink => _english ? 'Pink' : '粉色';
  String get yellow => _english ? 'Yellow' : '黄色';
  String get indigo => _english ? 'Indigo' : '靛蓝';
  String get immutableEvidence => _english
      ? 'Capture time, location result, photo number, and original hash remain unchanged.'
      : '拍摄时间、定位结果、照片编号和原图哈希不会被修改。';
  String get regenerationFailed => _english ? 'Regeneration failed' : '重新生成失败';
  String get allRecords => _english ? 'All records' : '全部记录';
  String get searchCaptures => _english ? 'Search records' : '搜索记录';
  String get searchCapturesHint => _english
      ? 'Search project, location, content, photographer, notes, address, or photo number'
      : '搜索项目、部位、内容、拍摄人、备注、地址或照片编号';
  String get clearSearch => _english ? 'Clear search' : '清空搜索';
  String get captureListLoadFailed => _english
      ? 'Could not load capture records. Please try again.'
      : '拍摄记录加载失败，请重试';
  String get loadMoreFailedRetry =>
      _english ? 'Could not load more. Tap to retry.' : '加载更多失败，点击重试';
  String get newCaptureRecords => _english ? 'New records' : '有新记录';
  String captureSearchNotes(String value) =>
      _english ? 'Notes: $value' : '备注：$value';
  String captureSearchAddress(String value) =>
      _english ? 'Address: $value' : '地址：$value';
  String captureSearchPhotoNumber(String value) =>
      _english ? 'Photo number: $value' : '照片编号：$value';
  String get settings => _english ? 'Settings' : '设置';
  String get diagnosticsAndFeedback =>
      _english ? 'Diagnostics and feedback' : '诊断与反馈';
  String get searchProjects => _english ? 'Search' : '搜索';
  String get searchProjectsHint => _english ? 'Search project name' : '搜索项目名称';
  String get noMatchingProjects =>
      _english ? 'No matching projects' : '没有匹配的项目';
  String get allProjects => _english ? 'All projects' : '全部项目';
  String get allYears => _english ? 'All years' : '全部年份';
  String get allMonths => _english ? 'All months' : '全部月份';
  String get allDays => _english ? 'All days' : '全部日期';
  String get monthSuffix => _english ? '' : '月';
  String get daySuffix => _english ? '' : '日';
  String get filteredEmpty =>
      _english ? 'No records match the current filters' : '没有符合筛选条件的记录';
  String get retryProcessing => _english ? 'Retry processing' : '重新处理';

  // Global settings and About
  String get appearance => _english ? 'Appearance' : '外观';
  String get theme => _english ? 'Theme' : '主题';
  String get systemTheme => _english ? 'System' : '跟随系统';
  String get lightTheme => _english ? 'Light' : '浅色';
  String get darkTheme => _english ? 'Dark' : '深色';
  String get language => _english ? 'Language' : '语言';
  String get systemLanguage => _english ? 'System' : '跟随系统';
  String get chinese => _english ? 'Chinese' : '简体中文';
  String get english => _english ? 'English' : 'English';
  String get newProjectDefaults =>
      _english ? 'New-project watermark defaults' : '新建项目水印默认值';
  String get appThemeColor => _english ? 'App theme color' : '应用主题色';
  String get about => _english ? 'About' : '关于';
  String get version => _english ? 'Version' : '版本';
  String get privacyStatements => _english
      ? 'No ads · No account · No cloud sync · No network permission · System camera'
      : '无广告 · 无账号 · 无云同步 · 发布包无网络权限 · 调用系统相机';
  String get repository => _english ? 'GitHub Repository' : 'GitHub 代码仓库';
  String get repositoryValue => siteMarkRepositoryUrl;
  String get openLinkFailed =>
      _english ? 'Could not open the browser' : '无法打开浏览器';
  String get privacySummary => _english
      ? 'The release APK requests no network permission; GitHub links open in an external browser. Foreground location is used only when requested, and a diagnostic bundle reaches the system share sheet only after confirmation.'
      : '发布包不申请网络权限；GitHub 链接交给外部浏览器。前台定位仅在用户主动请求时使用，诊断包仅在用户确认后交给系统分享面板。';
  String get license => _english ? 'License' : '许可证';
  String get licenseValue => 'Apache-2.0';
  String get licenses => _english ? 'Open-source licenses' : '开源许可证';
  String get opacityHint => _english
      ? 'Drag to set the new-project watermark opacity. Saved on release.'
      : '拖动以设置新建项目的水印透明度，松开后保存。';
  String get fontScaleHint => _english
      ? 'Drag the slider to adjust watermark font size (80%–160%).'
      : '拖动滑块调整水印字体大小（80%–160%）';

  // App-private storage accounting. System MediaStore photos are excluded.
  String get storageScope => _english
      ? 'SiteMark app data usage (system gallery excluded)'
      : 'SiteMark 应用内数据占用（不含系统相册）';
  // 二级菜单入口使用的短标签（storageScope 太长，不适合 ListTile 标题）。
  String get storageMenuLabel => _english ? 'Storage' : '储存';
  String get storageTotal => _english ? 'Total' : '合计';
  String get privateOriginals => _english ? 'Private originals' : '私有原图';
  String get privateWatermarked =>
      _english ? 'Private watermarked photos' : '私有水印成片';
  String get localExportFiles => _english ? 'Local export files' : '本地导出文件';
  String get databaseAndOther =>
      _english ? 'Database and other app documents' : '数据库及其他应用文档';
  String get refreshStorage => _english ? 'Refresh storage' : '刷新占用';
  String get manageRecords => _english ? 'Manage records' : '管理拍摄记录';
  String get clearLocalExports =>
      _english ? 'Clear local export files' : '清理本地导出文件';
  String get clearLocalExportsHint => _english
      ? 'Deletes only app-private ZIP files; shared copies and photos are kept.'
      : '仅删除应用私有目录中的 ZIP，已分享副本和照片不受影响。';
  String get clearLocalExportsPrompt => _english
      ? 'Delete all ZIP files from SiteMark private exports? Shared copies, photos, originals, and records are not affected.'
      : '确认删除 SiteMark 私有导出目录中的全部 ZIP？已分享副本、照片、原图和记录均不受影响。';
  String localExportsCleared(int count) =>
      _english ? 'Cleared $count local export file(s)' : '已清理 $count 个本地导出文件';
  String get clearLocalExportsFailed =>
      _english ? 'Could not clear local exports' : '本地导出文件清理失败';
  String get storageLoadFailed =>
      _english ? 'Could not read storage usage' : '无法读取存储占用';
  String get retry => _english ? 'Retry' : '重试';
  String get clear => _english ? 'Clear' : '清理';

  // Non-blocking location permission UX
  String get locationPermissionExplanation => _english
      ? 'Foreground location tags each capture with GPS coordinates. Capture still works if you decline; tap below to enable it once.'
      : '前台定位为每张照片记录 GPS 坐标。拒绝授权也可继续拍摄，点击下方按钮可一次性开启。';
  String get dismiss => _english ? 'Dismiss' : '关闭';
  String get enableLocation => _english ? 'Enable location' : '开启定位';
  String get openSettingsLabel => _english ? 'Open settings' : '打开设置';
  String get locationLabel => _english ? 'Location' : '定位';
  String get enabled => _english ? 'Enabled' : '已开启';
  String get disabled => _english ? 'Disabled' : '未开启';
  String get locationDisabledHint => _english
      ? 'Tap to request foreground location permission.'
      : '点击以请求前台定位授权。';
  String get locationPermanentlyDeniedHint => _english
      ? 'Location permission was denied. Open system settings to enable it.'
      : '定位权限已被拒绝，请前往系统设置开启。';

  // Capture list edit mode and batch actions (Task 4)
  String get editRecords => _english ? 'Edit records' : '编辑记录';
  String get done => _english ? 'Done' : '完成';
  String get selectAll => _english ? 'Select all' : '全选';
  String get deselectAll => _english ? 'Deselect all' : '取消全选';
  String get exportSelection => _english ? 'Export selection' : '导出所选';
  String get saveToGallery => _english ? 'Save to gallery' : '保存到相册';
  String get clearOriginals => _english ? 'Clear originals' : '清理原图';
  String get deleteAll => _english ? 'Delete all' : '全部删除';
  String selectedCount(int n) => _english ? '$n selected' : '已选 $n 张';
  String actionProgress(int completed, int total) =>
      _english ? 'Processing $completed/$total' : '正在处理 $completed/$total';
  String actionResult(int succeeded, int skipped, int failed) => _english
      ? 'Succeeded $succeeded, skipped $skipped, failed $failed'
      : '成功 $succeeded，跳过 $skipped，失败 $failed';
  String confirmClearOriginals(int n) => _english
      ? 'Confirm clearing $n originals? Watermarked photos, published images, database records and photo numbers are preserved.'
      : '确认清理 $n 张原图？水印成片、已发布图片、数据库记录和编号会保留。';
  String confirmDeleteAll(int n) => _english
      ? 'Confirm permanently deleting $n photos? Originals, watermarked photos, published images and database records will be deleted.'
      : '确认彻底删除 $n 张照片？将删除原图、成片、已发布图片和数据库记录。';
  String get originalRetained => _english ? 'Original retained' : '原图已保留';
  String get watermarkedPhoto => _english ? 'Watermarked' : '成片';
  String get originalPhoto => _english ? 'Original' : '原图';
  String get fileSize => _english ? 'File size' : '文件大小';
  String get resolution => _english ? 'Resolution' : '分辨率';
  String get format => _english ? 'Format' : '格式';
  String get publishedStatus => _english ? 'Published' : '已发布';
  String get publishedYes => _english ? 'Yes' : '是';
  String get publishedNo => _english ? 'No' : '否';
  String get watermarkedUnavailable =>
      _english ? 'Watermarked photo not yet available' : '成片尚未生成';
  String get originalClearedSnackbar => _english ? 'Original cleared' : '原图已清理';
  String get deleteOriginal => _english ? 'Delete original' : '删除原图';
  String get originalCleared => _english ? 'Original cleared' : '原图已清理';
  String get originalMissing => _english ? 'Original missing' : '原图缺失';

  // Motion & Android platform guidelines (motion-android-review Task 1)
  String get undo => _english ? 'Undo' : '撤销';
  String get deleteAction => _english ? 'Delete' : '删除';
  String clearOriginalsScheduled(int n) =>
      _english ? 'Clearing $n originals in 5 seconds' : '将在 5 秒后清理 $n 张原图';
  String get originalsClearedUndo => _english ? 'Originals cleared' : '原图已清理';
  String get dynamicColorTitle => _english ? 'Follow system color' : '跟随系统取色';
  String get dynamicColorSubtitle => _english
      ? 'Use wallpaper-based Material You colors on supported devices'
      : '在支持的设备上使用壁纸动态取色（Material You）';
  String get completionNotificationTitle =>
      _english ? 'Completion notifications' : '完成通知';
  String get completionNotificationSubtitle => _english
      ? 'Send a local notification when background processing finishes'
      : '后台处理完成后发送本地通知';
  String get notificationReadyTitle => _english ? 'Photo ready' : '照片处理完成';
  String notificationReadyBody(String photoNumber) => _english
      ? '$photoNumber finished processing. Tap to view.'
      : '照片 $photoNumber 已完成处理，点击查看';
  String get notificationChannelName => _english ? 'Photo processing' : '照片处理';
  String get notificationChannelDescription => _english
      ? 'Notifies when background photo processing finishes'
      : '后台照片处理完成时通知';
  String get filterAction => _english ? 'Filter' : '筛选';
  String get viewAction => _english ? 'View' : '查看';
  String get statusSemanticsPrefix => _english ? 'Status' : '状态';
  String photoSemanticsLabel(String photoNumber) =>
      _english ? 'Photo $photoNumber' : '照片 $photoNumber';
  String get fullscreenPhotoSemantics =>
      _english ? 'Fullscreen photo viewer' : '全屏查看照片';
  String get watermarkPreviewTitle => _english ? 'Watermark preview' : '水印预览';
  String get notificationPermissionDenied => _english
      ? 'Notification permission denied. You can enable it in system settings.'
      : '通知权限被拒绝，可在系统设置中开启';

  // Project backup restore (import)
  String get importProject => _english ? 'Import project backup' : '导入项目备份';
  String get importDialogTitle => _english ? 'Import project backup' : '导入项目备份';
  String importPhotoCount(int count) =>
      _english ? '$count photo(s)' : '$count 张照片';
  String get importIncludesOriginals =>
      _english ? 'Includes private originals' : '包含私有原图';
  String get importNoOriginals =>
      _english ? 'Watermarked photos only' : '仅水印成片';
  String get importWatermarkRestored => _english
      ? 'Project watermark settings will be restored.'
      : '将恢复该项目的水印设置。';
  String get importWatermarkDefault => _english
      ? 'The archive predates watermark backup; current defaults apply.'
      : '备份不含水印设置，将使用默认值。';
  String get importAction => _english ? 'Import' : '导入';
  String importingProgress(int completed, int total) =>
      _english ? 'Importing $completed/$total…' : '正在导入 $completed/$total…';
  String importSuccess(String name, int count) =>
      _english ? 'Imported "$name" ($count photo(s))' : '已导入「$name」（$count 张）';
  String get importFailed => _english ? 'Import failed' : '导入失败';
  String get importInvalidArchive =>
      _english ? 'Not a valid SiteMark project backup' : '不是有效的 SiteMark 项目备份';
  String get importSelectionUnsupported => _english
      ? 'Selection exports cannot be restored. Export a single project instead.'
      : '多选导出包暂不支持导入，请使用单项目导出包。';
  String get importNameConflict =>
      _english ? 'A project with this name already exists' : '已存在同名项目';

  // Unified backup and restore settings
  String get backupAndRestore => _english ? 'Backup & restore' : '备份与恢复';
  String get backupProjects => _english ? 'Back up projects' : '备份项目';
  String get restoreProjects => _english ? 'Restore projects' : '恢复项目';
  String get backupExplanation => _english
      ? 'Create a SiteMark ZIP for one or more projects. Photos already saved to the system gallery remain independent.'
      : '将一个或多个项目生成 SiteMark ZIP 备份。已保存到系统相册的照片独立保留。';
  String get restoreExplanation => _english
      ? 'Choose a ZIP exported by SiteMark. Regular photo-sharing ZIP files cannot be restored.'
      : '请选择由 SiteMark 导出的备份 ZIP；普通照片分享 ZIP 无法恢复。';
  String selectedProjectCount(int count) =>
      _english ? '$count project(s) selected' : '已选择 $count 个项目';
  String get continueLabel => _english ? 'Continue' : '继续';
  String get noProjectsToBackup =>
      _english ? 'No projects available to back up' : '暂无可备份项目';
  String get includePrivateOriginals =>
      _english ? 'Include private originals' : '包含私有原图';
  String get includePrivateOriginalsConsequence => _english
      ? 'The backup will be larger and take longer to create.'
      : '备份文件会更大，生成时间也会更长。';
  String get excludePrivateOriginals =>
      _english ? 'Exclude originals' : '不包含原图';
  String backingUpProgress(int completed, int total) =>
      _english ? 'Backing up $completed/$total' : '正在备份 $completed/$total';
  String get backupComplete => _english
      ? 'Backup created. Choose where to share or save it.'
      : '备份已生成，请选择分享或保存位置';
  String get backupSaved => _english ? 'Backup saved' : '备份已保存';
  String backupSavedWithOmissions(int count) => _english
      ? 'Backup saved; $count failed photo(s) were omitted as confirmed'
      : '备份已保存，已按你的选择跳过 $count 张失败记录';
  String get backupGeneratedNotSaved => _english
      ? 'Backup created, but not yet saved to the selected location'
      : '备份文件已生成，但尚未保存到所选位置';
  String get backupSaveFailed => _english
      ? 'Backup created, but it could not be saved. Try again or share it.'
      : '备份文件已生成，但保存失败；可再次保存或改用分享';
  String get saveAgain => _english ? 'Save again' : '再次保存';
  String get shareBackup => _english ? 'Share' : '分享';
  String get backupShared => _english ? 'Backup shared' : '备份已分享';
  String get backupShareFailed => _english
      ? 'Could not share the backup. You can try again.'
      : '无法分享备份，请重试';
  String get backupFailedFriendly =>
      _english ? 'Could not create the backup' : '无法生成备份';
  String backupProjectFailed(String projectName) => _english
      ? 'Could not back up "$projectName". Try again; if it still fails, select only this project and retry.'
      : '无法备份项目“$projectName”。请重试；若仍失败，请单独选择该项目备份。';
  String get chooseRestoreZip => _english ? 'Choose backup ZIP' : '选择备份 ZIP';
  String get restorePickerFailed => _english
      ? 'Could not open the backup file picker. Please try again.'
      : '无法打开备份文件选择器，请重试';
  String get restorePreview => _english ? 'Restore preview' : '恢复预览';
  String get restoreName => _english ? 'Name after restore' : '恢复后的项目名称';
  String get bundleRestoreRollback => _english
      ? 'All projects are restored together. If any item fails, this restore is rolled back completely.'
      : '所有项目将作为一个整体恢复；任一项目失败时，本次恢复会全部回滚。';
  String get restoreAction => _english ? 'Restore' : '恢复';
  String restoringProgress(int completed, int total) =>
      _english ? 'Restoring $completed/$total' : '正在恢复 $completed/$total';
  String get restoreComplete => _english ? 'Restore complete' : '恢复完成';
  String get backupInvalidArchive =>
      _english ? 'Not a valid SiteMark backup' : '不是有效的 SiteMark 备份';
  String get backupNotSiteMark =>
      _english ? 'This is not a SiteMark backup file' : '不是 SiteMark 备份文件';
  String get backupUnsupportedVersion =>
      _english ? 'This backup version is not supported' : '此备份版本暂不支持';
  String get backupCorrupted => _english
      ? 'The backup is corrupted or its checksum does not match'
      : '备份已损坏或校验不一致';
  String get backupSelectionNotRestorable => _english
      ? 'Photo sharing ZIP files cannot restore projects'
      : '照片分享 ZIP 不能用于恢复项目';
  String get backupRestoreNameConflict => _english
      ? 'A project name conflicts with an existing or selected project'
      : '项目名称与已有或所选项目冲突';
  String get backupStorageInsufficient => _english
      ? 'Not enough storage space to complete this operation'
      : '存储空间不足，无法完成操作';
  String get restoreFinalizationPending => _english
      ? 'Restore data is safely saved. Publication and visibility will finish automatically the next time the app starts.'
      : '恢复数据已安全保存，将在下次启动应用时自动完成发布和显示';
  String get restoreFailedRollback => _english
      ? 'Restore failed. Any changes from this restore were rolled back.'
      : '恢复失败，本次产生的内容已回滚';
  String get restoreFailedGeneral => _english
      ? 'Could not complete the restore. Please try again.'
      : '无法完成恢复，请重试';
  String get restoreUsesBackupWatermark =>
      _english ? 'Use watermark settings from this backup' : '使用备份中的水印设置';
  String restoreWatermarkSummary(
    String position,
    int opacityPercent,
    int fontPercent,
  ) => _english
      ? '$position · Opacity $opacityPercent% · Font $fontPercent%'
      : '$position · 透明度 $opacityPercent% · 字体 $fontPercent%';
  String get restoreUsesDefaultWatermark => _english
      ? 'No watermark settings in this backup; defaults will be used'
      : '备份未包含水印设置，将使用默认设置';
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppStrings.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppStrings> load(Locale locale) {
    return SynchronousFuture(AppStrings(locale));
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

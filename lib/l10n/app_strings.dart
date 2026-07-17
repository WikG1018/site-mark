import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sitemark/domain/app_links.dart';

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
  String get descriptionOptional =>
      _english ? 'Description (optional)' : '项目说明（选填）';
  String get save => _english ? 'Save' : '保存';
  String get localOnly => _english ? 'Local only' : '仅保存在本机';
  String get noAds => _english ? 'No ads · No cloud' : '无广告 · 无云端';
  String get captureRecords => _english ? 'Capture records' : '拍摄记录';
  String get noCaptures => _english ? 'No site records yet' : '暂无拍摄记录';
  String get capture => _english ? 'Capture' : '拍摄';
  String get newCapture => _english ? 'New site record' : '新建现场记录';
  String get workLocation => _english ? 'Work location' : '工程部位';
  String get workContent => _english ? 'Work content' : '工作内容';
  String get photographer => _english ? 'Photographer' : '拍摄人';
  String get notesOptional => _english ? 'Notes (optional)' : '备注（选填）';
  String get requiredField => _english ? 'This field is required' : '此项为必填';
  String get openSystemCamera => _english ? 'Open system camera' : '调用系统相机';
  String get captureLocationHint => _english
      ? 'Foreground location is requested once before capture. Capture still works if you decline.'
      : '拍摄前仅请求一次前台位置；拒绝授权也可以继续拍摄。';
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
  String get captureQueuedContinue => _english
      ? 'Photo queued for background processing. Continue shooting.'
      : '照片已加入后台处理，可继续拍摄';
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
  String get immutableEvidence => _english
      ? 'Capture time, location result, photo number, and original hash remain unchanged.'
      : '拍摄时间、定位结果、照片编号和原图哈希不会被修改。';
  String get regenerationFailed => _english ? 'Regeneration failed' : '重新生成失败';
  String get allRecords => _english ? 'All records' : '全部记录';
  String get settings => _english ? 'Settings' : '设置';
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
  String get about => _english ? 'About' : '关于';
  String get version => _english ? 'Version' : '版本';
  String get privacyStatements => _english
      ? 'No ads · No account · No cloud · System camera only · Local storage only'
      : '无广告 · 无账号 · 无云端 · 仅调用系统相机 · 仅保存在本机';
  String get repository => _english ? 'GitHub Repository' : 'GitHub 代码仓库';
  String get repositoryValue => siteMarkRepositoryUrl;
  String get openLinkFailed =>
      _english ? 'Could not open the browser' : '无法打开浏览器';
  String get privacySummary => _english
      ? 'Offline by design. No account, no SiteMark server, no ads, no analytics SDK. Foreground location is requested once before capture and stored only with the local record.'
      : '以离线使用为设计前提，不创建账号、不连接服务器、不展示广告、不含统计 SDK。拍摄前仅请求一次前台定位，结果只保存在本机记录中。';
  String get license => _english ? 'License' : '许可证';
  String get licenseValue => 'Apache-2.0';
  String get licenses => _english ? 'Open-source licenses' : '开源许可证';
  String get opacityHint => _english
      ? 'Drag to set the new-project watermark opacity. Saved on release.'
      : '拖动以设置新建项目的水印透明度，松开后保存。';
  String get fontScaleHint => _english
      ? 'Drag the slider to adjust watermark font size (80%–160%).'
      : '拖动滑块调整水印字体大小（80%–160%）';

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

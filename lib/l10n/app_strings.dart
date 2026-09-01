import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_failure_guidance.dart';
import 'package:sitemark/domain/capture_media_failure.dart';
import 'package:sitemark/domain/original_photo_state.dart';

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
  String get appTitleFull =>
      _english ? 'SiteMark Engineering Marks' : 'SiteMark 工程印记';
  String get projectNamePlaceholder =>
      _english ? 'Project name placeholder' : '项目名称占位';
  String get noProjects => _english ? 'No projects yet' : '还没有项目';
  String get noProjectsHint => _english
      ? 'Create an engineering project before recording the site.'
      : '先创建工程项目，再开始现场拍摄记录。';
  String get noActiveProjects => _english ? 'No active projects' : '暂无进行中的项目';
  String get noActiveProjectsHint => _english
      ? 'Create a project or restore one from backup.'
      : '可以新建项目，或从备份恢复项目。';
  String get noCompletedProjects =>
      _english ? 'No completed projects yet' : '暂无已完成的项目';
  String get noCompletedProjectsHint => _english
      ? 'Mark a project complete when site work is finished.'
      : '现场工作结束后，可将项目标记为已完成。';
  String get noArchivedProjects =>
      _english ? 'No archived projects yet' : '暂无已归档的项目';
  String get noArchivedProjectsHint => _english
      ? 'Archive finished projects to keep the active list clean.'
      : '归档已结束的项目，保持进行中列表整洁。';
  String get projectStatusFilterTitle => _english ? 'Project status' : '项目状态';
  String get projectStatusActive => _english ? 'Active' : '进行中';
  String get projectStatusCompleted => _english ? 'Completed' : '已完成';
  String get projectStatusArchived => _english ? 'Archived' : '已归档';
  String get pinProject => _english ? 'Pin project' : '置顶';
  String get unpinProject => _english ? 'Unpin project' : '取消置顶';
  String get markProjectCompleted => _english ? 'Mark completed' : '标记完成';
  String get archiveProject => _english ? 'Archive' : '归档';
  String get reopenProject => _english ? 'Reopen project' : '重新启用';
  String get restoreProjectToActive => _english ? 'Restore to active' : '恢复使用';
  String get projectPinnedBadge => _english ? 'Pinned' : '置顶';
  String projectPhotoCount(int count) =>
      _english ? (count == 1 ? '1 photo' : '$count photos') : '$count 张照片';
  String get noCaptureRecordsYet => _english ? 'No captures yet' : '暂无拍摄记录';
  String lastCaptureAtLabel(String value) =>
      _english ? 'Last capture: $value' : '最近拍摄：$value';
  String projectLifecycleProcessingBlocked(int count) => _english
      ? 'Cannot change status while $count capture(s) are still processing.'
      : '仍有 $count 张照片在拍摄或处理中，无法更改状态。';
  String projectLifecycleFailedConfirm(int count) => _english
      ? 'This project has $count failed capture(s). Continue anyway?'
      : '该项目有 $count 条失败记录，仍要继续吗？';
  String get projectLifecycleConflict =>
      _english ? 'Project status changed. Please try again.' : '项目状态已变化，请重试';
  String get projectLifecycleContinue => _english ? 'Continue' : '继续';
  String get projectStatusBannerCompleted => _english
      ? 'This project is completed. New captures are disabled.'
      : '项目已完成，不能继续拍摄。';
  String get projectStatusBannerArchived => _english
      ? 'This project is archived. New captures are disabled.'
      : '项目已归档，不能继续拍摄。';
  String get captureReadOnlyMessage => _english
      ? 'This project is not active, so new captures are disabled.'
      : '项目当前不可拍摄，无法新建记录。';
  String restoreStatusSummary({
    required int activeCount,
    required int completedCount,
    required int archivedCount,
  }) => _english
      ? 'Active $activeCount · Completed $completedCount · Archived $archivedCount'
      : '进行中 $activeCount、已完成 $completedCount、已归档 $archivedCount';
  String get viewArchivedProjects =>
      _english ? 'View archived projects' : '查看归档项目';
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
      ? 'System camera · background watermarking · continuous capture'
      : '系统相机拍摄 · 后台生成水印 · 支持连续拍摄';
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
          ? 'The original is missing, so the watermarked photo cannot be created. Return to the project and take the photo again; you can keep this failed record or delete it from the top-right menu.'
          : '原图已缺失，无法生成水印照片。请返回项目重新拍摄；也可保留此失败记录，或从右上角菜单删除记录。',
    CaptureFailureCode.originalModified =>
      _english
          ? 'The original does not match its capture-time checksum, so processing stopped. Keep the current original as evidence and take the photo again, or delete this failed record from the top-right menu.'
          : '原图内容与拍摄时校验值不一致，处理已停止。请保留现有原图作为证据并重新拍摄，或从右上角菜单删除此失败记录。',
    CaptureFailureCode.processingFailed =>
      _english
          ? 'Photo processing failed, but the original is retained. Select Retry processing; if it still fails, keep the original and take the photo again.'
          : '照片处理失败，但原图仍保留。请点击“重新处理”；若仍失败，请保留原图并重新拍摄。',
    CaptureFailureCode.unexpected =>
      _english
          ? 'The photo could not be processed for an unknown reason. If the original is retained, select Retry processing; otherwise take the photo again.'
          : '照片因未知原因处理失败。若原图仍保留，请点击“重新处理”；否则请重新拍摄。',
  };

  /// User-facing text for a batched media-operation failure. The enum itself
  /// carries no raw exception or file-path content, so these strings are the
  /// only surface that can show failure details.
  String captureMediaFailure(CaptureMediaFailure failure) => switch (failure) {
    CaptureMediaFailure.recordMissing =>
      _english ? 'Capture record does not exist' : '拍摄记录不存在',
    CaptureMediaFailure.clearStatusNotAllowed =>
      _english
          ? 'Only ready or failed captures can have originals cleared'
          : '仅可清除就绪或失败记录的原始照片',
    CaptureMediaFailure.deleteStatusNotAllowed =>
      _english
          ? 'Only ready or failed captures can be deleted'
          : '仅可删除就绪或失败状态的记录',
    CaptureMediaFailure.republishStatusNotAllowed =>
      _english ? 'Only ready captures can be republished' : '仅可就绪状态的记录重新发布',
    CaptureMediaFailure.projectReadOnly =>
      _english
          ? 'This capture belongs to a completed or archived project'
          : '该记录所属项目已完结或归档，为只读状态',
    CaptureMediaFailure.originalMissing =>
      _english ? 'Original photo is unexpectedly missing' : '原图意外缺失，无法完成操作',
    CaptureMediaFailure.renderedPhotoMissing =>
      _english ? 'Rendered photo is missing' : '水印照片文件缺失',
    CaptureMediaFailure.operationFailed =>
      _english ? 'Operation failed. Please try again.' : '操作失败，请重试。',
  };
  String captureFailureGuidanceMessage(CaptureFailureGuidance guidance) {
    if (guidance.surface == CaptureFailureGuidanceSurface.list) {
      return switch (guidance.code) {
        CaptureFailureCode.cameraUnavailable =>
          _english
              ? 'The system camera was unavailable. Open the record to see available actions.'
              : '系统相机当时不可用。请打开记录查看可用操作。',
        CaptureFailureCode.queueUnavailable =>
          _english
              ? 'Background processing was delayed. Open the record to see available actions.'
              : '后台处理曾延迟。请打开记录查看可用操作。',
        CaptureFailureCode.originalMissing =>
          _english
              ? 'The original is missing, so no watermarked photo was created. Open the record to see available actions.'
              : '原图已缺失，无法生成水印照片。请打开记录查看可用操作。',
        CaptureFailureCode.originalModified =>
          _english
              ? 'The original checksum does not match, so processing stopped. Open the record to see available actions.'
              : '原图校验值不一致，处理已停止。请打开记录查看可用操作。',
        CaptureFailureCode.processingFailed =>
          _english
              ? 'Photo processing failed. Open the record to see available actions.'
              : '照片处理失败。请打开记录查看可用操作。',
        CaptureFailureCode.unexpected =>
          _english
              ? 'The photo could not be processed. Open the record to see available actions.'
              : '照片因未知原因处理失败。请打开记录查看可用操作。',
      };
    }

    final reason = switch (guidance.code) {
      CaptureFailureCode.cameraUnavailable =>
        _english ? 'The system camera was unavailable.' : '系统相机当时不可用。',
      CaptureFailureCode.queueUnavailable =>
        _english ? 'Background processing was delayed.' : '后台处理曾延迟。',
      CaptureFailureCode.originalMissing =>
        _english
            ? 'The original is missing, so no watermarked photo was created.'
            : '原图已缺失，无法生成水印照片。',
      CaptureFailureCode.originalModified =>
        _english
            ? 'The original does not match its capture-time checksum, so processing stopped.'
            : '原图内容与拍摄时校验值不一致，处理已停止。',
      CaptureFailureCode.processingFailed =>
        _english ? 'Photo processing failed.' : '照片处理失败。',
      CaptureFailureCode.unexpected =>
        _english
            ? 'The photo could not be processed for an unknown reason.'
            : '照片因未知原因处理失败。',
    };

    if (guidance.originalState == null) {
      if (!guidance.projectActive) {
        return _english
            ? '$reason The original photo state could not be checked, so Retry processing is unavailable for now. The project is read-only; keep this record and reopen the details later to check again.'
            : '$reason 无法检查原图状态，暂不提供重新处理。项目当前为只读状态；可保留此记录，稍后重新打开详情检查。';
      }
      return _english
          ? '$reason The original photo state could not be checked, so Retry processing is unavailable for now. Keep this record and reopen the details later to check again, or use the top-right menu to delete it.'
          : '$reason 无法检查原图状态，暂不提供重新处理。可保留此记录，稍后重新打开详情检查，或使用右上角菜单删除记录。';
    }
    if (!guidance.projectActive) {
      return _english
          ? '$reason The project is read-only, so the record cannot be retried or deleted. Keep the record, or restore the project to active and open it again to see available actions.'
          : '$reason 项目当前为只读状态，不能重新处理或删除记录。可保留此记录，或先将项目恢复为进行中，再打开记录查看可用操作。';
    }
    if (guidance.originalState == OriginalPhotoState.missing) {
      return _english
          ? '$reason The original is currently missing, so retry is unavailable. Return to the project and take the photo again; you can keep this failed record or use the top-right menu to delete it.'
          : '$reason 原图当前缺失，无法重新处理。请返回项目重新拍摄；也可保留此失败记录，或使用右上角菜单删除记录。';
    }
    if (guidance.originalState == OriginalPhotoState.cleared) {
      return _english
          ? '$reason The original has been cleared, so retry is unavailable. Return to the project and take the photo again; you can keep this failed record or use the top-right menu to delete it.'
          : '$reason 原图已清理，无法重新处理。请返回项目重新拍摄；也可保留此失败记录，或使用右上角菜单删除记录。';
    }
    if (guidance.code == CaptureFailureCode.originalMissing) {
      return _english
          ? '$reason Return to the project and take the photo again; you can keep this failed record or use the top-right menu to delete it.'
          : '$reason 请返回项目重新拍摄；也可保留此失败记录，或使用右上角菜单删除记录。';
    }
    if (guidance.code == CaptureFailureCode.originalModified) {
      return _english
          ? '$reason Keep the current original as evidence and take the photo again, or use the top-right menu to delete this failed record.'
          : '$reason 请保留现有原图作为证据并重新拍摄，或使用右上角菜单删除此失败记录。';
    }
    if (guidance.canRetry) {
      return _english
          ? '$reason The original is retained. Select Retry processing; if it still fails, keep the original and take the photo again.'
          : '$reason 原图仍保留。请点击“重新处理”；若仍失败，请保留原图并重新拍摄。';
    }
    return _english
        ? '$reason Keep the record or use the top-right menu to delete it; return to the project to take the photo again.'
        : '$reason 可保留此记录或使用右上角菜单删除，并返回项目重新拍摄。';
  }

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
  String get fieldRecordTab => _english ? 'Field record' : '现场记录';
  String get fileInfoTab => _english ? 'File info' : '文件信息';
  String get fileInfoInspectionFailed => _english
      ? 'File information could not be checked because the local photo is temporarily unavailable. Keep this record and check again.'
      : '无法检查文件信息，本地照片可能暂时不可访问。请保留此记录并重新检查。';
  String get recheckFileInfo => _english ? 'Check again' : '重新检查';
  String get fullFileName => _english ? 'Full file name' : '完整文件名';
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
  String get projects => _english ? 'Projects' : '项目';
  String get searchCaptures => _english ? 'Search records' : '搜索记录';
  String get searchCapturesHint => _english
      ? 'Search project, location, content, photographer, notes, address, or photo number'
      : '搜索项目、部位、内容、拍摄人、备注、地址或照片编号';
  String get clearSearch => _english ? 'Clear search' : '清空搜索';
  String get captureListLoadFailed => _english
      ? 'Local capture records could not be read. Please try again.'
      : '无法读取本机拍摄记录，请重试。';
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
  String monthFilterLabel(int month) => _english ? 'Month $month' : '$month月';
  String dayFilterLabel(int day) => _english ? 'Day $day' : '$day日';
  String get filterRecords => _english ? 'Filter records' : '筛选记录';
  String get resetFilters => _english ? 'Reset' : '重置';
  String get applyFilters => _english ? 'Apply' : '应用';
  String get removeFilter => _english ? 'Remove filter' : '移除筛选条件';
  String get removeProjectFilter =>
      _english ? 'Remove project filter' : '移除项目筛选';
  String get removeYearFilter => _english ? 'Remove year filter' : '移除年份筛选';
  String get removeMonthFilter => _english ? 'Remove month filter' : '移除月份筛选';
  String get removeDayFilter => _english ? 'Remove day filter' : '移除日期筛选';
  String get deletedProject => _english ? 'Deleted project' : '已删除项目';
  String get filteredEmpty =>
      _english ? 'No records match the current filters' : '没有符合筛选条件的记录';
  String get retryProcessing => _english ? 'Retry processing' : '重新处理';

  // Global settings and About
  String get settingsCaptureAndRecords =>
      _english ? 'Capture & records' : '拍摄与记录';
  String get settingsDataAndSafety => _english ? 'Data & safety' : '数据与安全';
  String get settingsApplication => _english ? 'Application' : '应用';
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
      ? 'Add GPS to photos (capture works without it).'
      : '为照片记录 GPS（拒绝后仍可拍摄）';
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
  String get selectRecords => _english ? 'Select' : '选择';
  String get done => _english ? 'Done' : '完成';
  String get selectAll => _english ? 'Select all' : '全选';
  String get deselectAll => _english ? 'Deselect all' : '取消全选';
  String get exportSelection => _english ? 'Export selection' : '导出所选';
  String get saveToGallery => _english ? 'Save to gallery' : '保存到相册';
  String get clearOriginals => _english ? 'Clear originals' : '清理原图';
  String get deleteAll => _english ? 'Delete all' : '全部删除';
  String currentVisibleDate(String date) =>
      _english ? 'Current visible date: $date' : '当前可见日期：$date';
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

  /// User-facing import failure that never includes raw exception text.
  String get importFailedFriendly => _english
      ? 'Could not import the project. Choose a valid SiteMark project backup and try again; if it still fails, free some storage space or use another backup.'
      : '无法导入该项目。请选择有效的 SiteMark 项目备份后重试；若仍失败，请释放存储空间或换用其他备份。';
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
  String get backupFailedFriendly => _english
      ? 'Project data or files could not be read, so the backup was not created. Try again; if it still fails, back up one project at a time.'
      : '无法读取项目数据或文件，因而无法生成备份。请重试；若仍失败，请逐个项目备份。';
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
  String get backupInvalidArchive => _english
      ? 'The selected ZIP is not a valid SiteMark project backup. Choose a ZIP created with Back up projects in SiteMark.'
      : '所选 ZIP 不是有效的 SiteMark 项目备份。请选择由 SiteMark“备份项目”生成的 ZIP。';
  String get backupNotSiteMark => _english
      ? 'The selected ZIP is not a project backup exported by SiteMark. Choose a ZIP created with Back up projects in SiteMark.'
      : '所选 ZIP 不是 SiteMark 导出的项目备份。请选择由 SiteMark“备份项目”生成的 ZIP。';
  String get backupUnsupportedVersion => _english
      ? 'This backup is newer than this app can read. Update SiteMark, then choose the backup again.'
      : '此备份版本高于当前应用支持范围。请先升级 SiteMark，再重新选择该备份。';
  String get backupCorrupted => _english
      ? 'The backup is corrupted or its checksum does not match. Choose another SiteMark backup and try again.'
      : '备份已损坏或校验不一致。请选择其他 SiteMark 备份后重试。';
  String get backupSelectionNotRestorable => _english
      ? 'The selected ZIP is a photo-sharing archive and contains no restorable project data. Choose a ZIP created with Back up projects.'
      : '所选 ZIP 是照片分享包，不含可恢复的项目数据。请选择通过“备份项目”生成的 ZIP。';
  String get backupRestoreNameConflict => _english
      ? 'A restore project name conflicts with an existing project or another selected name. Start restore again, change each conflicting name in the preview, then restore.'
      : '恢复项目名称与现有项目或本次所选名称冲突。请重新开始恢复，并在预览中修改冲突名称后再恢复。';
  String get backupStorageInsufficient => _english
      ? 'Not enough storage space to complete this operation. Free some space and try again.'
      : '存储空间不足，无法完成操作。请释放空间后重试。';
  String get restoreFinalizationPending => _english
      ? 'Restore data is safely saved but is not visible yet. Restart SiteMark to finish the restore automatically.'
      : '恢复数据已安全保存，但尚未完成显示。请重启 SiteMark，应用会自动完成恢复。';
  String get restoreFailedRollback => _english
      ? 'One or more projects could not be restored, so all changes from this restore were rolled back. Choose the original backup and restore again; if it still fails, restore single-project backups one at a time.'
      : '一个或多个项目恢复失败，本次更改已全部回滚。请重新选择原备份进行恢复；若仍失败，请改用单项目备份逐个恢复。';
  String get restoreFailedGeneral => _english
      ? 'An error prevented the restore from completing. Choose the backup and restore again; if it still fails, restore single-project backups one at a time.'
      : '恢复过程中发生错误，未能完成恢复。请重新选择备份进行恢复；若仍失败，请改用单项目备份逐个恢复。';
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

  String get privacyProtection => _english ? 'Privacy' : '隐私保护';
  String get diagnosticsStoredLocally => _english
      ? 'Diagnostic records stay on this device and are never uploaded automatically.'
      : '诊断记录只保存在本机，不会自动上传。';
  String get diagnosticBundlePrivacyNotice => _english
      ? 'The diagnostic bundle does not include photos, project names, work content, photographers, coordinates, or original file paths; the file is handed to the system share sheet only after you choose to share it.'
      : '诊断包不包含照片、项目名称、工程内容、拍摄人、位置坐标或原图路径；'
            '只有你主动点击分享后，文件才会交给系统分享面板。';
  String get diagnosticsRetentionHint => _english
      ? 'Diagnostic records are kept for at most 7 days, with a 2 MB size limit.'
      : '诊断记录最多保留 7 天，空间上限为 2 MB。';
  String get generateAndShareDiagnosticBundle =>
      _english ? 'Generate and share diagnostic bundle' : '生成并分享诊断包';
  String get shareDiagnosticBundleTitle =>
      _english ? 'Share diagnostic bundle?' : '分享诊断包？';
  String get shareDiagnosticBundleContent => _english
      ? 'Includes: app version, system environment, storage statistics, operation results, and timings.\n\n'
            'Does not include: photos, project names, work content, photographers, coordinates, file paths, or raw exceptions.\n\n'
            'The system share sheet opens only after you confirm.'
      : '包含：应用版本、系统环境、存储统计、操作结果与耗时。\n\n'
            '不包含：照片、项目名称、工程内容、拍摄人、位置坐标、文件路径和原始异常。\n\n'
            '确认后才会打开系统分享面板。';
  String get confirmGenerate => _english ? 'Generate' : '确认生成';
  String get diagnosticBundleFailed => _english
      ? 'Could not generate the diagnostic bundle. Please try again.'
      : '诊断包生成失败，请稍后重试';
  String get clearLocalDiagnostics =>
      _english ? 'Clear local diagnostic records' : '清除本机诊断记录';
  String get clearDiagnosticsTitle =>
      _english ? 'Clear diagnostic records?' : '清除诊断记录？';
  String get clearDiagnosticsContent => _english
      ? 'Only local diagnostic events will be cleared. Photos, projects, and backups are not deleted.'
      : '只清除本机诊断事件，不会删除照片、项目或备份。';
  String get platformDifferences => _english ? 'Platform differences' : '平台差异';
  String get backgroundProcessingDescription => _english
      ? 'Watermark processing finishes automatically in the background; photos that are not yet processed are caught up in the background.'
      : '水印处理在拍摄后自动于后台完成，未完成的照片会在后台继续补拍。';
  String get backgroundProcessingIosNote => _english
      ? 'On iOS, background catch-up is scheduled opportunistically by the system when the device is idle; it is not guaranteed to run right after a capture.'
      : '在 iOS 上，后台补拍由系统安排在设备空闲时机会性执行，不保证拍完立刻处理。';
  String get photoLibraryDeleteConfirmationNote => _english
      ? 'A system confirmation dialog may appear when photos are deleted from the photo library.'
      : '删除系统相册中的照片时，可能弹出系统确认框。';
  String get locationAccuracyNote => _english
      ? 'Location precision depends on the system authorization; the system may only provide an approximate location.'
      : '定位精度由系统授权决定，系统可能只提供模糊位置。';
  String get backupWaitForProcessingTitle =>
      _english ? 'Wait for photos to finish processing' : '请等待照片处理完成';
  String backupWaitForProcessingMessage(int count) => _english
      ? '$count photo(s) are still processing. Wait until they finish so the backup is complete.'
      : '有 $count 张照片仍在处理中。为避免备份遗漏，请处理完成后再试。';
  String get backupFailedRecordsTitle =>
      _english ? 'Some photos failed processing' : '存在处理失败的照片';
  String backupFailedRecordsMessage(int count) => _english
      ? '$count failed record(s) will not be included. Retry those photos first, or back up only completed records.'
      : '有 $count 张失败记录不会进入备份。建议先返回项目重新处理；'
            '也可以明确选择仅备份已完成记录。';
  String get backupReturnToProcess => _english ? 'Go back and retry' : '返回处理';
  String get backupCompletedRecordsOnly =>
      _english ? 'Back up completed records only' : '仅备份已完成记录';
  String get backupEmptyProjectHint => _english
      ? 'Empty projects can also be backed up. The description and watermark settings are kept.'
      : '空白项目也可以备份，项目说明和水印设置会保留。';
  String get gotIt => _english ? 'Got it' : '知道了';
  String diagnosticBundleSummary({
    required String generatedAt,
    required int eventCount,
  }) => _english
      ? 'SiteMark diagnostic bundle\n'
            'Generated at: $generatedAt\n'
            'Event count: $eventCount\n'
            'Privacy: no photos, project names, work content, people, locations, file paths, or raw exceptions.\n'
      : 'SiteMark 诊断包\n'
            '生成时间：$generatedAt\n'
            '事件数量：$eventCount\n'
            '隐私：不包含照片、项目名称、工程内容、人员、位置、文件路径或原始异常。\n';
  String get captureNotFound =>
      _english ? 'Capture not found or deleted' : '拍摄记录不存在或已删除';
  String get captureLoadFailed => _english
      ? 'Could not load the capture. Go back and try again.'
      : '拍摄记录加载失败，请返回后重试';
  String get createProjectFailed => _english
      ? 'Could not create the project. Please try again.'
      : '项目创建失败，请稍后重试';

  // NAS sync (settings, data & safety)
  String get nasSync => _english ? 'NAS sync' : 'NAS 同步';
  String get nasSyncSubtitle => _english
      ? 'Auto-upload watermarked photos to your NAS'
      : '把水印成片自动上传到你的 NAS';
  String get nasEnable => _english ? 'Enable NAS sync' : '启用 NAS 同步';
  String get nasProtocol => _english ? 'Protocol' : '协议';
  String get nasProtocolWebdav => 'WebDAV';
  String get nasProtocolSftp => 'SFTP';
  String get nasProtocolSmb => 'SMB';
  String get nasHost => _english ? 'Server address' : '服务器地址';
  String get nasHostHint => _english ? 'e.g. 192.168.1.10' : '例如 192.168.1.10';
  String get nasPort => _english ? 'Port (optional)' : '端口（可选）';
  String get nasPortHintWebdav => _english ? '80 or 443' : '80 或 443';
  String get nasPortHintSftp => _english ? '22' : '22';
  String get nasPortHintSmb => _english ? '445' : '445';
  String get nasUsername => _english ? 'Username' : '用户名';
  String get nasPassword => _english ? 'Password' : '密码';
  String get nasRootPath => _english ? 'Root path' : '根目录';
  String get nasRootPathHint => _english
      ? 'e.g. /SiteMark'
      : '例如 /SiteMark';
  String get nasSmbRootPathHint => _english
      ? 'Start with the share name, e.g. /media/SiteMark'
      : '以共享名开头，例如 /media/SiteMark';
  String get nasSecureTls => _english ? 'Use HTTPS' : '使用 HTTPS';
  String get nasAcceptInvalidTls => _english
      ? 'Accept self-signed certificates'
      : '接受自签名证书';
  String get nasWifiOnly => _english ? 'Upload on Wi-Fi only' : '仅 Wi-Fi 上传';
  String get nasTestConnection => _english ? 'Test connection' : '测试连接';
  String get nasTestSucceeded =>
      _english ? 'Connection successful' : '连接成功';
  String get nasSave => _english ? 'Save' : '保存';
  String get nasSaved => _english ? 'Saved' : '已保存';
  String get nasRetryFailed => _english
      ? 'Retry failed uploads'
      : '重试失败的上传';
  String get nasPrivacyNote => _english
      ? 'Uploads go only to the NAS you configure. Passwords stay in system secure storage and never enter backups or diagnostics.'
      : '上传仅面向你配置的 NAS。密码保存在系统安全存储，不会进入备份或诊断。';
  String get nasFingerprintTitle => _english
      ? 'Verify server fingerprint'
      : '验证服务器指纹';
  String nasFingerprintBody(String fingerprint) => _english
      ? 'First connection to this SFTP server. Verify the host key fingerprint before trusting it:\n\n$fingerprint'
      : '首次连接该 SFTP 服务器。请核对主机密钥指纹后再信任：\n\n$fingerprint';
  String get nasFingerprintAccept =>
      _english ? 'Trust and continue' : '信任并继续';
  String get nasHostRequired =>
      _english ? 'Enter the server address first' : '请先填写服务器地址';
  String nasQueueSummary(int pending, int failed, int uploaded) => _english
      ? 'Pending $pending · Failed $failed · Uploaded $uploaded'
      : '待上传 $pending · 失败 $failed · 已上传 $uploaded';
  String get nasErrorConnectionFailed => _english
      ? 'Cannot reach the server. Check the address and network.'
      : '无法连接服务器，请检查地址和网络。';
  String get nasErrorAuthFailed => _english
      ? 'Incorrect username or password'
      : '用户名或密码不正确';
  String get nasErrorTimeout => _english ? 'Connection timed out' : '连接超时';
  String get nasErrorTlsError => _english
      ? 'TLS or certificate error'
      : 'TLS 或证书错误';
  String get nasErrorTlsUnsupported => _english
      ? 'WebDAV over HTTPS is unavailable on this platform. Use HTTP, SFTP or SMB.'
      : '当前平台的 WebDAV 暂不支持 HTTPS，可改用 HTTP 或 SFTP/SMB。';
  String get nasErrorHostKeyChanged => _english
      ? 'The server fingerprint changed. Run the connection test again to confirm.'
      : '服务器指纹已变化，请重新测试连接并确认。';
  String get nasErrorProtocolError => _english
      ? 'The server returned an unexpected response'
      : '服务器响应异常';
  String get nasErrorQuotaInsufficient => _english
      ? 'The NAS is out of storage space'
      : 'NAS 存储空间不足';
  String get nasErrorPathInvalid =>
      _english ? 'Invalid remote path' : '远程路径无效';
  String get nasErrorLocalIo =>
      _english ? 'The local photo file is missing' : '本地照片文件缺失';
  String get nasErrorConfigInvalid =>
      _english ? 'The configuration is incomplete' : '配置不完整';
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

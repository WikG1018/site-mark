# SiteMark 记录列表与存储管理实施计划

> **供执行 Agent 使用：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务执行。每个步骤使用复选框跟踪状态。

**目标：** 缩短新照片实际文件名与列表标题，禁止创建同名/同安全键项目，修正筛选按钮和全选切换，并在总设置中加入应用内存储统计与导出文件清理。

**实现方式：** 保留 Drift schema 4 和旧记录编号；只修改新记录编号分配。纯 Dart 存储服务读取数据库原图路径和应用文档目录，Riverpod 向设置页提供可刷新状态。筛选和选择逻辑继续由现有共享组件承载。

**技术栈：** Flutter、Dart、Riverpod、Drift/SQLite、path_provider、Flutter Widget Test。

## 全局约束

- 分支：`agent/sitemark-record-list-storage`，基线：已合并 PR #7 的 `origin/main`。
- 不迁移或重命名旧记录、旧相册文件和旧导出内容。
- 新文件名为 `{安全化项目名称}-SM-{yyyyMMdd}-{全应用当日序号}.jpg`。
- 不新增数据库 schema、Android 权限、网络访问或第三方依赖。
- 项目名称冲突必须在数据库写入边界拦截，并在中英文表单中显示。
- 存储合计不包含系统相册 `Pictures/SiteMark`。
- 每项行为先写失败测试，再写最小实现。

---

### Task 1（任务 1）：新照片短文件名与项目唯一性

**文件：**

- 修改：`lib/domain/photo_number.dart`
- 新建：`lib/domain/project_name.dart`
- 修改：`lib/data/app_database.dart`
- 修改：`lib/features/projects/project_form_screen.dart`
- 修改：`lib/l10n/app_strings.dart`
- 修改：`test/domain/photo_number_test.dart`
- 新建：`test/domain/project_name_test.dart`
- 修改：`test/data/app_database_test.dart`
- 修改：`test/widget_test.dart`

**接口：**

- `formatPhotoNumber({projectName, capturedAt, sequence})` 返回不含项目 UUID 的编号。
- `normalizedProjectNameKey(name)` 和 `safeProjectFileNameKey(name)` 产生冲突比较键。
- `ProjectNameConflictException` 区分显示名称冲突和安全文件名冲突。

- [ ] **步骤 1：写失败测试**

```dart
expect(
  formatPhotoNumber(
    projectName: '云湖之城',
    capturedAt: DateTime(2026, 7, 17),
    sequence: 3,
  ),
  '云湖之城-SM-20260717-003',
);
await database.createProject(id: 'a', name: 'Cloud Site');
expect(
  () => database.createProject(id: 'b', name: ' cloud   site '),
  throwsA(isA<ProjectNameConflictException>()),
);
```

再建立两个不同项目，在同一天依次完成拍摄，断言编号尾号为 `001`、`002`；建立 `A/B` 后拒绝 `A:B`。

- [ ] **步骤 2：运行并确认失败**

```powershell
flutter test test/domain/photo_number_test.dart test/domain/project_name_test.dart test/data/app_database_test.dart test/widget_test.dart
```

预期：旧格式仍包含 `~projectId`，且项目冲突未抛出新异常。

- [ ] **步骤 3：实现新编号与项目冲突检查**

`markCaptured` 在事务中查询所有项目同一天已有编号，解析最后一个 `-` 后的序号并分配全局最大值加一。`createProject` 在同一事务中比较规范化显示键和安全文件名键，冲突时抛出 `ProjectNameConflictException`。表单捕获异常，将错误写入项目名称输入框并恢复保存按钮。

- [ ] **步骤 4：运行聚焦测试并提交**

```powershell
flutter test test/domain/photo_number_test.dart test/domain/project_name_test.dart test/data/app_database_test.dart test/widget_test.dart
git add -- lib/domain/photo_number.dart lib/domain/project_name.dart lib/data/app_database.dart lib/features/projects/project_form_screen.dart lib/l10n/app_strings.dart test/domain/photo_number_test.dart test/domain/project_name_test.dart test/data/app_database_test.dart test/widget_test.dart
git commit -m "feat: shorten new photo names"
```

### Task 2（任务 2）：短列表标题与方角居中筛选按钮

**文件：**

- 新建：`lib/domain/capture_display_name.dart`
- 修改：`lib/features/capture/capture_record_card.dart`
- 修改：`lib/features/capture/compact_filter_menu.dart`
- 修改：`lib/features/capture/capture_date_filter_bar.dart`
- 修改：`lib/features/capture/all_captures_screen.dart`
- 新建：`test/domain/capture_display_name_test.dart`
- 修改：`test/features/capture/capture_filter_ui_test.dart`

**接口：**

- `captureListDisplayName({capturedAt, photoNumber, fallback})` 对新旧编号均返回 `yyyy-MM-dd · 序号`。
- `CompactFilterMenu` 固定 44dp 高、10dp 圆角、文字中心和右侧箭头。

- [ ] **步骤 1：写失败测试**

```dart
expect(
  captureListDisplayName(
    capturedAt: DateTime(2026, 7, 17),
    photoNumber: '云湖之城~uuid-SM-20260717-003',
    fallback: '南地块',
  ),
  '2026-07-17 · 003',
);
```

Widget 测试在 360dp 下读取按钮和文字中心点，断言横向误差小于 1dp；解析按钮 shape，断言是 10dp `RoundedRectangleBorder`，四个筛选仍在同一行且无溢出。

- [ ] **步骤 2：运行并确认失败**

```powershell
flutter test test/domain/capture_display_name_test.dart test/features/capture/capture_filter_ui_test.dart
```

- [ ] **步骤 3：实现共享显示名和筛选几何**

记录卡标题使用新 helper，不修改详情页。筛选按钮使用 `Stack(alignment: Alignment.center)` 居中文字，箭头 `Positioned(right: 6)`；按钮之间加入 6dp 间距，全部记录的项目筛选仍与年月日保持单行。

- [ ] **步骤 4：验证并提交**

```powershell
flutter test test/domain/capture_display_name_test.dart test/features/capture/capture_filter_ui_test.dart
git add -- lib/domain/capture_display_name.dart lib/features/capture/capture_record_card.dart lib/features/capture/compact_filter_menu.dart lib/features/capture/capture_date_filter_bar.dart lib/features/capture/all_captures_screen.dart test/domain/capture_display_name_test.dart test/features/capture/capture_filter_ui_test.dart
git commit -m "fix: refine capture list presentation"
```

### Task 3（任务 3）：全选与取消全选切换

**文件：**

- 修改：`lib/features/capture/capture_selection_controller.dart`
- 修改：`lib/features/capture/all_captures_screen.dart`
- 修改：`lib/features/projects/project_detail_screen.dart`
- 修改：`lib/l10n/app_strings.dart`
- 修改：`test/features/capture/capture_selection_controller_test.dart`
- 修改：`test/features/capture/capture_filter_ui_test.dart`

**接口：**

- `allSelected(eligibleIds)` 判断当前可选集合是否全部选中。
- `toggleAll(eligibleIds)` 在全选和清空之间切换。

- [ ] **步骤 1：写失败测试**

```dart
controller.toggleAll(['a', 'b']);
expect(controller.selectedIds, {'a', 'b'});
controller.toggleAll(['a', 'b']);
expect(controller.selectedIds, isEmpty);
```

Widget 测试连续点击两次 AppBar 全选按钮，断言全部 Checkbox 先选中再取消，并确认 `captured`/`rendering` 始终未选。

- [ ] **步骤 2：运行失败、实现、验证并提交**

```powershell
flutter test test/features/capture/capture_selection_controller_test.dart test/features/capture/capture_filter_ui_test.dart
git add -- lib/features/capture/capture_selection_controller.dart lib/features/capture/all_captures_screen.dart lib/features/projects/project_detail_screen.dart lib/l10n/app_strings.dart test/features/capture/capture_selection_controller_test.dart test/features/capture/capture_filter_ui_test.dart
git commit -m "fix: toggle select all records"
```

### Task 4（任务 4）：存储统计、管理入口与导出清理

**文件：**

- 新建：`lib/domain/app_storage_usage.dart`
- 新建：`lib/workflow/app_storage_service.dart`
- 修改：`lib/data/app_database.dart`
- 修改：`lib/app.dart`
- 修改：`lib/features/settings/global_settings_screen.dart`
- 修改：`lib/l10n/app_strings.dart`
- 新建：`test/workflow/app_storage_service_test.dart`
- 修改：`test/features/settings/global_settings_screen_test.dart`

**接口：**

```dart
abstract interface class StorageUsageService {
  Future<AppStorageUsage> load();
  Future<ClearExportsResult> clearExports();
}
```

`AppStorageUsage` 保存 `originalBytes`、`renderedBytes`、`exportBytes`、`databaseAndOtherBytes`，并提供 `totalBytes`。`formatStorageBytes` 以 B/KB/MB/GB 显示。

- [ ] **步骤 1：写失败的服务测试**

在临时目录创建已知大小的原图、`rendered` JPEG、`exports` ZIP 和 `sitemark.sqlite`，断言分类及总量；调用 `clearExports()` 后只删除 ZIP，其他文件保持不变。

- [ ] **步骤 2：写失败的设置页测试**

通过 Provider override 注入 fake `StorageUsageService`，断言显示总量和四类数据；点击刷新触发第二次 `load`；点击管理记录进入 `/records`；确认清理对话框后调用 `clearExports` 并刷新。

- [ ] **步骤 3：实现服务和设置区块**

服务对路径去重并忽略不存在文件。设置页使用 `FutureProvider.autoDispose`，错误状态显示重试按钮；清理按钮在导出占用为 0 时禁用。二次确认文案明确只删除本地 ZIP。

- [ ] **步骤 4：验证并提交**

```powershell
flutter test test/workflow/app_storage_service_test.dart test/features/settings/global_settings_screen_test.dart
git add -- lib/domain/app_storage_usage.dart lib/workflow/app_storage_service.dart lib/data/app_database.dart lib/app.dart lib/features/settings/global_settings_screen.dart lib/l10n/app_strings.dart test/workflow/app_storage_service_test.dart test/features/settings/global_settings_screen_test.dart
git commit -m "feat: show and manage app storage"
```

### Task 5（任务 5）：同步文档、完整验证和交付

**文件：**

- 修改：`README.md`
- 修改：`docs/current-product-architecture.md`
- 修改：`docs/record-watermark-settings.md`
- 修改：`docs/decision-records.md`
- 修改：`docs/verification-v0.2.0-alpha.md`

- [ ] **步骤 1：更新当前事实**

把新文件名、项目唯一性、筛选样式、全选切换和设置存储区块写入当前文档；从 README P1 中移除已经完成的“显示私有存储占用”，但保留尚未完成的诊断包和面向用户的发布说明。

- [ ] **步骤 2：运行完整验证**

```powershell
flutter analyze
flutter test
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
./android/gradlew.bat -p android :sitemark_system_api:testDebugUnitTest
flutter build apk --debug
git diff --check origin/main...HEAD
```

- [ ] **步骤 3：提交、复制 APK 并创建 Draft PR**

```powershell
git add -- README.md docs/current-product-architecture.md docs/record-watermark-settings.md docs/decision-records.md docs/verification-v0.2.0-alpha.md
git commit -m "docs: update record and storage behavior"
Copy-Item build/app/outputs/flutter-apk/app-debug.apk C:/Users/Administrator/Desktop/mac/SiteMark-record-list-storage-debug.apk -Force
git push -u origin agent/sitemark-record-list-storage
gh pr create --repo WikG1018/site-mark --base main --head agent/sitemark-record-list-storage --draft --title "feat: improve record list and storage management"
```

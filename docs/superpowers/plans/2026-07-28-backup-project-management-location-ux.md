# SiteMark 备份恢复、项目管理与定位提示实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将备份与恢复迁移到设置并支持可完整恢复的多项目备份，同时增加项目重命名、可靠删除，并精简拍摄页定位提示。

**Architecture:** 保留现有单项目 ZIP v1/v2 契约，在其外增加一个带哈希清单的多项目 bundle；Dart 服务负责编排、事务标记和界面进度，Rust 只负责安全的 ZIP/哈希操作。项目删除通过持久化清理标记实现“数据库立即移除、私有文件可重试清理”，后台工作遇到已删除记录按现有 `missing` 结果安全结束。

**Tech Stack:** Flutter 3.44.6、Dart、Riverpod、GoRouter、Drift/SQLite、Rust、flutter_rust_bridge、zip、WorkManager、Android 系统文件选择器与分享面板。

## Global Constraints

- 保持无账号、无云端、离线优先，不增加网络权限。
- 不自动扫描用户存储空间；恢复文件必须由用户通过系统文件选择器选择。
- 现有 v1、v2 单项目备份继续支持恢复；普通跨项目分享 ZIP 仍不可恢复。
- 多项目恢复必须整包成功或整包回滚，进程中断后可在下次启动继续清理。
- 项目重命名只影响项目显示名及之后新照片，历史编号、路径、文件名和水印保持不变。
- 删除项目不删除、不修改已经保存到 Android 系统相册的照片，也不提供该选项。
- 拍摄按钮不得触发定位授权；仅用户主动点击定位说明卡片时请求权限。
- 所有新增文案同时提供中文和英文，360dp 宽度不得溢出。

---

## 文件结构与职责

**新增文件**

- `lib/workflow/project_deletion_service.dart`：项目删除预览、持久化清理标记、私有文件清理和启动重试。
- `lib/workflow/project_bundle_service.dart`：多项目备份生成、备份识别、准备恢复、整包回滚。
- `lib/features/settings/sections/backup_restore_section_screen.dart`：设置中的“备份与恢复”入口页。
- `lib/features/settings/sections/project_backup_selection_screen.dart`：项目单选、多选、全选和原图选项。
- `lib/features/projects/project_restore_flow.dart`：单项目/多项目恢复预览、名称编辑、进度和结果提示。
- `test/workflow/project_deletion_service_test.dart`、`test/workflow/project_bundle_service_test.dart`：服务层事务与失败恢复测试。
- `test/features/settings/sections/backup_restore_section_screen_test.dart`、`test/features/settings/sections/project_backup_selection_screen_test.dart`：设置与项目选择界面测试。

**重点修改文件**

- `rust/src/api/image_core.rs`：多项目 bundle 外层 ZIP、清单、哈希、限制和解包。
- `lib/src/rust/api/image_core.dart`、`lib/src/rust/frb_generated*.dart`、`rust/src/frb_generated.rs`：由 flutter_rust_bridge 重新生成。
- `lib/workflow/project_export_service.dart`、`lib/workflow/project_import_service.dart`：支持指定输出路径和预分配项目 ID。
- `lib/workflow/app_startup_recovery.dart`：串联导入、bundle 和项目删除中断清理，同时不阻断核心恢复。
- `lib/data/app_database.dart`：项目重命名和删除预览所需查询。
- `lib/app.dart`：服务 Provider、新设置路由与项目选择路由。
- `lib/features/projects/project_detail_screen.dart`：项目操作菜单、重命名和删除交互。
- `lib/features/projects/project_list_screen.dart`：移除首页恢复图标。
- `lib/features/capture/capture_form_screen.dart`：移除固定定位提示卡片。
- `lib/l10n/app_strings.dart`：新增中英文文案并删除废弃固定提示。

---

### Task 1: 项目重命名数据库契约

**Files:**
- Modify: `lib/data/app_database.dart`
- Test: `test/data/app_database_test.dart`

**Interfaces:**
- Produces: `Future<Project> renameProject({required String projectId, required String name})`
- Consumes: `normalizedProjectNameKey(String)`、`safeProjectFileNameKey(String)`、`ProjectNameConflictException`

- [ ] **Step 1: 写重命名失败测试**

```dart
test('renameProject rejects display and safe-file-name conflicts', () async {
  await database.createProject(id: 'a', name: '东区');
  await database.createProject(id: 'b', name: '西区');
  await expectLater(
    database.renameProject(projectId: 'b', name: '  东区  '),
    throwsA(isA<ProjectNameConflictException>()),
  );
  await database.createProject(id: 'c', name: 'A/B');
  await expectLater(
    database.renameProject(projectId: 'b', name: 'A:B'),
    throwsA(isA<ProjectNameConflictException>()),
  );
});
```

- [ ] **Step 2: 运行测试并确认红灯**

Run: `flutter test test/data/app_database_test.dart --plain-name "renameProject rejects display and safe-file-name conflicts"`

Expected: FAIL，提示 `renameProject` 未定义。

- [ ] **Step 3: 实现排除自身的重名检查与更新**

```dart
Future<Project> renameProject({
  required String projectId,
  required String name,
}) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty || trimmedName.length > 120) {
    throw ArgumentError.value(name, 'name');
  }
  return transaction(() async {
    final current = await projectById(projectId);
    if (current == null) throw StateError('Project does not exist');
    final displayKey = normalizedProjectNameKey(trimmedName);
    final safeKey = safeProjectFileNameKey(trimmedName);
    for (final existing in await select(projects).get()) {
      if (existing.id == projectId) continue;
      if (normalizedProjectNameKey(existing.name) == displayKey) {
        throw const ProjectNameConflictException(
          ProjectNameConflictKind.displayName,
        );
      }
      if (safeProjectFileNameKey(existing.name) == safeKey) {
        throw const ProjectNameConflictException(
          ProjectNameConflictKind.safeFileName,
        );
      }
    }
    await (update(projects)..where((row) => row.id.equals(projectId))).write(
      ProjectsCompanion(
        name: Value(trimmedName),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await projectById(projectId))!;
  });
}
```

- [ ] **Step 4: 增加历史记录不变测试并跑绿**

```dart
final before = await database.capturesForProject('a');
await database.renameProject(projectId: 'a', name: '东区新名称');
final after = await database.capturesForProject('a');
expect(after.single.photoNumber, before.single.photoNumber);
expect(after.single.originalPath, before.single.originalPath);
```

Run: `flutter test test/data/app_database_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/data/app_database.dart test/data/app_database_test.dart
git commit -m "feat: add safe project renaming"
```

---

### Task 2: 可恢复的项目删除服务

**Files:**
- Create: `lib/workflow/project_deletion_service.dart`
- Modify: `lib/app.dart`
- Modify: `lib/workflow/app_startup_recovery.dart`
- Test: `test/workflow/project_deletion_service_test.dart`
- Test: `test/workflow/app_startup_recovery_test.dart`
- Test: `test/workflow/capture_processor_test.dart`

**Interfaces:**
- Produces: `ProjectDeletionPreview`、`ProjectDeletionResult`、`PendingProjectDeletion`
- Produces: `ProjectDeletionService.preview(String)`、`deleteProject(String)`、`cleanupInterruptedDeletions()`
- Consumes: `AppDatabase.capturesForProject`、`CaptureOutputPaths.renderedPhotoPath`、`PrivateFileStore.deleteIfExists`

- [ ] **Step 1: 写“保留系统相册照片”的失败测试**

```dart
test('deleteProject removes private files and rows but never published URIs', () async {
  final files = _RecordingPrivateFileStore();
  final service = ProjectDeletionService(
    database: database,
    capturePaths: _FakeCaptureOutputPaths(),
    files: files,
    pendingStore: _MemoryProjectDeletionPendingStore(),
  );
  final result = await service.deleteProject('project-1');
  expect(await database.projectById('project-1'), isNull);
  expect(files.deleted, containsAll(['/private/original.jpg', '/rendered/c1.jpg']));
  expect(files.deleted, isNot(contains('content://media/published')));
  expect(result.cleanupPending, isFalse);
});
```

- [ ] **Step 2: 运行测试并确认服务不存在**

Run: `flutter test test/workflow/project_deletion_service_test.dart`

Expected: FAIL，提示 `ProjectDeletionService` 未定义。

- [ ] **Step 3: 实现持久化删除标记和服务**

```dart
class PendingProjectDeletion {
  const PendingProjectDeletion({required this.projectId, required this.paths});
  final String projectId;
  final List<String> paths;
}

class ProjectDeletionService {
  Future<ProjectDeletionResult> deleteProject(String projectId) async {
    final captures = await database.capturesForProject(projectId);
    final paths = <String>{};
    for (final capture in captures) {
      paths.add(capture.originalPath);
      paths.add(await capturePaths.renderedPhotoPath(capture.id));
    }
    final pending = PendingProjectDeletion(
      projectId: projectId,
      paths: paths.toList(growable: false),
    );
    await pendingStore.write(pending);
    await database.deleteProjectCascade(projectId);
    final cleaned = await _deletePaths(pending.paths);
    if (cleaned) await pendingStore.clear(projectId);
    return ProjectDeletionResult(cleanupPending: !cleaned);
  }
}
```

生产 `AppProjectDeletionPendingStore` 将 JSON 标记放到 `<documents>/cleanup/project-<id>.json`。它只记录应用私有路径，绝不记录或调用 `publishedUri`。

- [ ] **Step 4: 增加清理失败和启动重试测试**

```dart
test('failed private cleanup keeps marker and retries on startup', () async {
  files.failOnceFor.add('/rendered/c1.jpg');
  final result = await service.deleteProject('project-1');
  expect(result.cleanupPending, isTrue);
  expect(pendingStore.items, isNotEmpty);
  await service.cleanupInterruptedDeletions();
  expect(pendingStore.items, isEmpty);
});
```

同时锁定删除确认所需统计和后台安全结束：

```dart
final preview = await service.preview('project-1');
expect(preview.captureCount, 3);
expect(preview.privateOriginalCount, 2);

await service.deleteProject('project-1');
expect(await processor.process('capture-queued'), CaptureProcessResult.missing);
```

将 `AppStartupRecovery` 新增 `cleanupInterruptedProjectDeletions` 回调，并分别 `try/catch`，保证清理失败不阻断相机、定位和队列恢复。

Run: `flutter test test/workflow/project_deletion_service_test.dart test/workflow/app_startup_recovery_test.dart test/workflow/capture_processor_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/workflow/project_deletion_service.dart lib/workflow/app_startup_recovery.dart lib/app.dart test/workflow/project_deletion_service_test.dart test/workflow/app_startup_recovery_test.dart test/workflow/capture_processor_test.dart
git commit -m "feat: add durable project deletion"
```

---

### Task 3: Rust 多项目备份包格式

**Files:**
- Modify: `rust/src/api/image_core.rs`
- Modify generated: `rust/src/frb_generated.rs`
- Modify generated: `lib/src/rust/api/image_core.dart`
- Modify generated: `lib/src/rust/frb_generated.dart`
- Modify generated: `lib/src/rust/frb_generated.io.dart`
- Modify generated: `lib/src/rust/frb_generated.web.dart`
- Test: `rust/tests/core_test.rs`

**Interfaces:**
- Produces: `export_project_bundle(ExportProjectBundleRequest) -> ExportProjectResult`
- Produces: `read_project_bundle(String) -> ProjectBundlePreview`
- Produces: `extract_project_bundle_entry(ExtractProjectBundleEntryRequest)`
- Bundle constants: `MAX_BUNDLE_PROJECTS = 100`、`MAX_BUNDLE_ENTRY_BYTES = 8 GiB`、`MAX_BUNDLE_TOTAL_BYTES = 16 GiB`

- [ ] **Step 1: 写 bundle 往返和恶意归档失败测试**

```rust
#[test]
fn project_bundle_round_trip_and_hash_validation() {
    let result = export_project_bundle(ExportProjectBundleRequest {
        output_zip_path: bundle_path.clone(),
        projects: vec![ProjectBundleSource {
            project_id: "project-1".into(),
            project_name: "东区".into(),
            archive_path: project_zip.clone(),
        }],
    }).unwrap();
    let preview = read_project_bundle(bundle_path).unwrap();
    assert_eq!(preview.projects.len(), 1);
    assert_eq!(preview.projects[0].archive_sha256, sha256_file(project_zip).unwrap());
    assert!(!result.archive_sha256.is_empty());
}
```

另写用例拒绝：`../escape.zip`、重复项目 ID、101 个项目、清单哈希不一致、超限 entry、普通 selection ZIP。

- [ ] **Step 2: 运行 Rust 测试确认红灯**

Run: `cargo test --manifest-path rust/Cargo.toml project_bundle -- --nocapture`

Expected: FAIL，bundle 类型和函数未定义。

- [ ] **Step 3: 实现外层清单和安全 ZIP 操作**

```rust
#[derive(Serialize, Deserialize)]
struct ProjectBundleManifest {
    app: String,
    kind: String,
    schema_version: u32,
    created_at: String,
    projects: Vec<ProjectBundleManifestEntry>,
}

#[derive(Serialize, Deserialize)]
struct ProjectBundleManifestEntry {
    project_id: String,
    project_name: String,
    archive_path: String,
    archive_sha256: String,
}
```

外层 ZIP 只允许 `bundle.json` 和 `projects/<safe-project-id>.zip`；内部 ZIP 使用 `CompressionMethod::Stored`，避免重复压缩和过高 CPU；读取时先校验清单、数量、entry 大小和累计大小，再校验 SHA-256。解包仍使用 `.tmp` 写入、校验完成后原子改名。

- [ ] **Step 4: 重新生成 flutter_rust_bridge 文件**

Run: `flutter_rust_bridge_codegen generate`

Expected: 生成的 Dart/Rust bridge 包含三个新函数及其请求/预览类型，命令退出码为 0。

- [ ] **Step 5: 运行 Rust 全量质量门**

Run: `cargo fmt --manifest-path rust/Cargo.toml --check`

Run: `cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings`

Run: `cargo test --manifest-path rust/Cargo.toml`

Expected: 全部 PASS，无 clippy 警告。

- [ ] **Step 6: 提交**

```bash
git add rust/src/api/image_core.rs rust/src/frb_generated.rs rust/tests/core_test.rs lib/src/rust
git commit -m "feat: add restorable multi-project bundles"
```

---

### Task 4: Dart 多项目备份与整包恢复编排

**Files:**
- Create: `lib/workflow/project_bundle_service.dart`
- Modify: `lib/workflow/project_export_service.dart`
- Modify: `lib/workflow/project_import_service.dart`
- Modify: `lib/platform/platform_services.dart`
- Modify: `lib/app.dart`
- Test: `test/workflow/project_bundle_service_test.dart`
- Test: `test/workflow/project_export_test.dart`
- Test: `test/workflow/project_import_test.dart`

**Interfaces:**
- Produces: `ProjectBackupService.exportProjects({required List<String> projectIds, required bool includeOriginals, void Function(int completed, int total)? onProgress})`
- Produces: `ProjectBundleService.prepareRestore(String zipPath)`、`restorePrepared({required PreparedProjectRestore prepared, required Map<String, String> projectNames, void Function(int completed, int total)? onProgress})`、`discardPrepared(PreparedProjectRestore prepared)`
- Produces: `BundleRestorePendingStore` 与 `PendingBundleRestore`
- Modifies: `ProjectImportService.importProject(..., String? projectId)`，传入 ID 时不再内部生成 UUID

- [ ] **Step 1: 写单选兼容和多选 bundle 失败测试**

```dart
test('one selected project keeps the existing single-project archive', () async {
  final result = await service.exportProjects(
    projectIds: ['p1'],
    includeOriginals: true,
  );
  expect(result.kind, ProjectBackupKind.singleProject);
  expect(images.bundleRequests, isEmpty);
});

test('multiple projects create one bundle from isolated project archives', () async {
  final result = await service.exportProjects(
    projectIds: ['p1', 'p2'],
    includeOriginals: false,
  );
  expect(result.kind, ProjectBackupKind.bundle);
  expect(images.bundleRequests.single.projects.length, 2);
});
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `flutter test test/workflow/project_bundle_service_test.dart`

Expected: FAIL，`ProjectBackupService` 未定义。

- [ ] **Step 3: 让单项目导出支持调用方指定临时输出路径**

```dart
Future<ExportProjectResult> exportProject({
  required String projectId,
  required bool includeOriginals,
  String? outputZipPath,
}) async {
  final outputPath = outputZipPath ?? await exportPaths.projectZipPath(projectId);
  return images.export(
    ExportProjectRequest(
      projectId: project.id,
      projectName: project.name,
      outputZipPath: outputPath,
      includeOriginals: includeOriginals,
      watermark: ExportWatermarkSettings(
        position: project.watermarkPosition,
        opacity: project.watermarkOpacity,
        accentColorArgb: project.watermarkAccentColorArgb,
        fontScale: project.watermarkFontScale,
      ),
      photos: photos,
    ),
  );
}
```

为 bundle 新增 `ProjectBundlePaths`：最终文件位于 `exports/sitemark-backup-<timestamp>.zip`，内部单项目临时文件位于 `imports/bundle-staging-<uuid>/projects/`，完成或取消后删除整个临时目录。

- [ ] **Step 4: 实现备份编排**

```dart
Future<ProjectBackupResult> exportProjects({
  required List<String> projectIds,
  required bool includeOriginals,
  void Function(int completed, int total)? onProgress,
}) async {
  if (projectIds.isEmpty) throw StateError('Select at least one project');
  if (projectIds.length == 1) {
    final result = await projectExporter.exportProject(
      projectId: projectIds.single,
      includeOriginals: includeOriginals,
    );
    return ProjectBackupResult.single(result.outputZipPath);
  }
  // 为每个项目生成隔离的单项目 ZIP，再调用 Rust exportProjectBundle。
}
```

- [ ] **Step 5: 写整包失败回滚和进程中断测试**

```dart
test('bundle restore rolls back every planned project when item two fails', () async {
  importer.failForSource = 'p2.zip';
  await expectLater(
    service.restorePrepared(prepared, {'p1': '东区', 'p2': '西区'}),
    throwsA(isA<ProjectBundleRestoreException>()),
  );
  expect(await database.getProjects(), isEmpty);
  expect(bundlePendingStore.items, isEmpty);
});

test('startup cleanup removes planned ids even if kill happened before progress update', () async {
  bundlePendingStore.items.add(PendingBundleRestore(
    bundleId: 'b1',
    stagingDirectory: '/staging/b1',
    plannedProjectIds: ['new-p1', 'new-p2'],
  ));
  await service.cleanupInterruptedBundleRestores();
  expect(await database.projectById('new-p1'), isNull);
});
```

- [ ] **Step 6: 实现预分配 ID、持久标记和整包回滚**

```dart
final planned = <PreparedProjectRestoreItem>[
  for (final item in preview.projects)
    PreparedProjectRestoreItem(
      sourceProjectId: item.projectId,
      targetProjectId: uuid.v4(),
      archivePath: await extractInnerArchive(item),
      preview: await importer.inspect(extractedPath),
    ),
];

await pendingStore.write(PendingBundleRestore(
  bundleId: bundleId,
  stagingDirectory: stagingDirectory,
  plannedProjectIds: planned.map((item) => item.targetProjectId).toList(),
));
```

逐个调用 `importProject(projectId: targetProjectId, ...)`。任何失败都调用 `ProjectDeletionService.deleteProject` 清理所有计划 ID；删除服务自己的持久标记接管残留文件后，bundle 标记才可清除。

- [ ] **Step 7: 运行服务层测试**

Run: `flutter test test/workflow/project_bundle_service_test.dart test/workflow/project_export_test.dart test/workflow/project_import_test.dart`

Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add lib/workflow/project_bundle_service.dart lib/workflow/project_export_service.dart lib/workflow/project_import_service.dart lib/platform/platform_services.dart lib/app.dart test/workflow/project_bundle_service_test.dart test/workflow/project_export_test.dart test/workflow/project_import_test.dart
git commit -m "feat: orchestrate project bundle backup and restore"
```

---

### Task 5: 启动恢复顺序与故障隔离

**Files:**
- Modify: `lib/workflow/app_startup_recovery.dart`
- Modify: `lib/app.dart`
- Test: `test/workflow/app_startup_recovery_test.dart`
- Test: `test/app_lifecycle_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `cleanupInterruptedImports()`、`cleanupInterruptedBundleRestores()`、`cleanupInterruptedProjectDeletions()`
- Preserves: `recoverCamera()`、`resolveLocations()`、`reconcileQueue()` 必须始终继续执行

- [ ] **Step 1: 写三种清理互不阻断的失败测试**

```dart
test('all cleanup failures remain isolated from core recovery', () async {
  final events = <String>[];
  final recovery = AppStartupRecovery(
    cleanupInterruptedImports: () async => throw StateError('import'),
    cleanupInterruptedBundleRestores: () async => throw StateError('bundle'),
    cleanupInterruptedProjectDeletions: () async => throw StateError('delete'),
    recoverCamera: () async => events.add('camera'),
    resolveLocations: () async => events.add('location'),
    reconcileQueue: () async => events.add('queue'),
  );
  await recovery.run();
  expect(events, ['camera', 'location', 'queue']);
});
```

- [ ] **Step 2: 运行测试确认构造函数不匹配**

Run: `flutter test test/workflow/app_startup_recovery_test.dart`

Expected: FAIL，缺少 bundle/delete 清理参数。

- [ ] **Step 3: 实现固定顺序和逐项隔离**

```dart
Future<void> run() async {
  for (final cleanup in [
    cleanupInterruptedImports,
    cleanupInterruptedBundleRestores,
    cleanupInterruptedProjectDeletions,
  ]) {
    try { await cleanup(); } catch (_) {}
  }
  await recoverCamera();
  await resolveLocations();
  await reconcileQueue();
}
```

先清理单项目导入，再清理 bundle 计划项目，最后清理删除标记中的私有文件。更新所有测试构造点，不能以可选空回调掩盖漏接 Provider。

- [ ] **Step 4: 运行生命周期测试**

Run: `flutter test test/workflow/app_startup_recovery_test.dart test/app_lifecycle_test.dart test/widget_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/workflow/app_startup_recovery.dart lib/app.dart test/workflow/app_startup_recovery_test.dart test/app_lifecycle_test.dart test/widget_test.dart
git commit -m "fix: recover interrupted backup and deletion work"
```

---

### Task 6: 设置中的备份与恢复界面

**Files:**
- Create: `lib/features/settings/sections/backup_restore_section_screen.dart`
- Create: `lib/features/settings/sections/project_backup_selection_screen.dart`
- Create: `lib/features/projects/project_restore_flow.dart`
- Modify: `lib/features/settings/global_settings_screen.dart`
- Modify: `lib/features/projects/project_list_screen.dart`
- Modify: `lib/app.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/settings/global_settings_screen_test.dart`
- Test: `test/features/settings/sections/backup_restore_section_screen_test.dart`
- Test: `test/features/settings/sections/project_backup_selection_screen_test.dart`
- Test: `test/features/projects/project_list_screen_test.dart`

**Interfaces:**
- Consumes: `ProjectBackupService.exportProjects`、`ProjectBundleService.prepareRestore/restorePrepared/discardPrepared`
- Produces routes: `/settings/backup-restore`、`/settings/backup-restore/backup`
- Produces keys: `backup-restore-menu`、`backup-projects`、`restore-projects`、`select-all-projects`、`backup-continue`

- [ ] **Step 1: 写设置入口和首页移除图标测试**

```dart
expect(find.byKey(const Key('backup-restore-menu')), findsOneWidget);
expect(find.byKey(const Key('import-project')), findsNothing);
```

Run: `flutter test test/features/settings/global_settings_screen_test.dart test/features/projects/project_list_screen_test.dart`

Expected: FAIL，设置入口不存在且首页仍有导入按钮。

- [ ] **Step 2: 注册路由与设置菜单**

```dart
(
  Icons.settings_backup_restore_outlined,
  strings.backupAndRestore,
  '/settings/backup-restore',
),
```

在 `lib/app.dart` 的 settings 子路由加入 `BackupRestoreSectionScreen`，其子路由加入 `ProjectBackupSelectionScreen`；从 `ProjectListScreen` 删除 `import-project` 的 `IconButton`。

- [ ] **Step 3: 写项目选择全选/取消全选测试**

```dart
await tester.tap(find.byKey(const Key('select-all-projects')));
await tester.pump();
expect(find.text('已选择 3 个项目'), findsOneWidget);
await tester.tap(find.byKey(const Key('select-all-projects')));
await tester.pump();
expect(find.text('已选择 0 个项目'), findsOneWidget);
```

- [ ] **Step 4: 实现项目选择和备份进度**

选择页通过 `database.watchProjects()` 展示项目；空项目禁止继续。继续后显示“包含私有原图”确认，执行期间使用不可关闭的进度对话框，成功后调用 `shareFileServiceProvider.shareFile(result.outputZipPath)`。

```dart
final result = await ref.read(projectBackupServiceProvider).exportProjects(
  projectIds: selectedIds.toList(growable: false),
  includeOriginals: includeOriginals,
  onProgress: (completed, total) => progress.value = (completed, total),
);
await ref.read(shareFileServiceProvider).shareFile(result.outputZipPath);
```

- [ ] **Step 5: 实现恢复说明、预览、名称编辑和取消清理**

恢复按钮先弹说明对话框，用户确认后调用只允许 ZIP 的文件选择器。`PreparedProjectRestore` 的每个项目显示照片数、原图情况和名称输入框；提交前逐项调用现有名称冲突规则，并检查本批次名称互相冲突。取消、返回或页面销毁时调用 `discardPrepared` 清理提取的临时文件。

- [ ] **Step 6: 添加中英文文案**

至少增加：`backupAndRestore`、`backupProjects`、`restoreProjects`、`backupExplanation`、`restoreExplanation`、`selectedProjectCount`、`includePrivateOriginals`、`bundleRestoreRollback`、`backupInvalidArchive`、`backupStorageInsufficient`。中文和英文 getter 必须在同一提交完成。

- [ ] **Step 7: 运行界面测试**

Run: `flutter test test/features/settings/global_settings_screen_test.dart test/features/settings/sections/backup_restore_section_screen_test.dart test/features/settings/sections/project_backup_selection_screen_test.dart test/features/projects/project_list_screen_test.dart`

Expected: PASS，并且 360dp 测试无 overflow exception。

- [ ] **Step 8: 提交**

```bash
git add lib/features/settings lib/features/projects/project_restore_flow.dart lib/features/projects/project_list_screen.dart lib/app.dart lib/l10n/app_strings.dart test/features/settings test/features/projects/project_list_screen_test.dart
git commit -m "feat: move backup and restore into settings"
```

---

### Task 7: 项目详情重命名和删除交互

**Files:**
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/capture/capture_filter_ui_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `AppDatabase.renameProject`、`ProjectDeletionService.preview/deleteProject`
- Produces keys: `project-actions`、`rename-project`、`delete-project`、`confirm-delete-project`

- [ ] **Step 1: 写操作菜单和删除后返回测试**

```dart
expect(find.byKey(const Key('project-actions')), findsOneWidget);
await tester.tap(find.byKey(const Key('project-actions')));
await tester.tap(find.byKey(const Key('delete-project')));
expect(find.textContaining('系统相册中的照片会保留'), findsOneWidget);
await tester.tap(find.byKey(const Key('confirm-delete-project')));
await tester.pumpAndSettle();
expect(router.routeInformationProvider.value.uri.path, '/');
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `flutter test test/features/capture/capture_filter_ui_test.dart --plain-name "project actions rename and delete"`

Expected: FAIL，操作菜单不存在。

- [ ] **Step 3: 实现 PopupMenu、重命名对话框和刷新**

```dart
final renamed = await ref.read(databaseProvider).renameProject(
  projectId: widget.projectId,
  name: controller.text,
);
if (!mounted) return;
setState(() {
  _projectFuture = Future.value(renamed);
});
```

对话框复用新建项目的校验文案；冲突时留在对话框并显示具体错误。历史记录列表不重建编号或路径。

- [ ] **Step 4: 实现删除预览和结果处理**

确认框显示项目名、记录数、私有原图数，并明确“系统相册和已导出备份会保留”。确认后调用删除服务；数据库删除成功即 `context.go('/')`。若 `cleanupPending == true`，提示“项目已删除，残留私有文件将在下次启动继续清理”。

- [ ] **Step 5: 运行项目详情测试**

Run: `flutter test test/features/capture/capture_filter_ui_test.dart test/widget_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add lib/features/projects/project_detail_screen.dart lib/l10n/app_strings.dart test/features/capture/capture_filter_ui_test.dart test/widget_test.dart
git commit -m "feat: manage project names and deletion"
```

---

### Task 8: 移除固定定位提示并保留首次授权卡片

**Files:**
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Create: `test/features/capture/capture_form_screen_test.dart`
- Test: `test/workflow/location_permission_service_test.dart`

**Interfaces:**
- Preserves: `LocationPermissionPromptArea`、`LocationPermissionService.dismiss/request/openSettings`
- Removes: `captureLocationHint` 及表单底部固定 `Card`

- [ ] **Step 1: 写固定提示不存在、首次卡片仍存在的测试**

```dart
expect(find.text('拍摄前仅请求一次前台位置；拒绝授权也可以继续拍摄。'), findsNothing);
expect(find.byKey(const Key('location-permission-prompt')), findsOneWidget);
```

增加授权态和已关闭态测试，两者都必须找不到 `location-permission-prompt`。

- [ ] **Step 2: 运行测试确认固定提示仍存在**

Run: `flutter test test/features/capture/capture_form_screen_test.dart`

Expected: FAIL，固定提示仍被渲染。

- [ ] **Step 3: 删除固定 Card 和废弃文案**

从 `_CaptureFormBody` 删除包含 `strings.captureLocationHint` 的 `Card`；删除 `AppStrings.captureLocationHint`。保留顶部 `LocationPermissionPromptArea(prompt: permissionPrompt)` 及其动画、关闭持久化和主动授权逻辑，不把授权请求移动到拍摄按钮。

- [ ] **Step 4: 运行定位与拍摄页测试**

Run: `flutter test test/features/capture/capture_form_screen_test.dart test/workflow/location_permission_service_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/features/capture/capture_form_screen.dart lib/l10n/app_strings.dart test/features/capture/capture_form_screen_test.dart test/workflow/location_permission_service_test.dart
git commit -m "fix: show location guidance only when needed"
```

---

### Task 9: 文档、全量回归与可合并检查

**Files:**
- Modify: `README.md`
- Modify: `docs/release-checklist.md`
- Verify: all changed production and test files

**Interfaces:**
- Documents: 设置 → 备份与恢复、单/多项目 ZIP、项目删除保留相册照片、恢复不自动发布相册
- No version bump in this task；版本号由下一次独立发布流程决定

- [ ] **Step 1: 更新用户说明**

README 将“从首页导入项目备份”改为“设置 → 备份与恢复”，写明单项目、多项目、原图选项、普通分享 ZIP 不可恢复，以及删除项目不会删除系统相册照片。`docs/release-checklist.md` 增加单项目和多项目端到端恢复、失败回滚、项目重命名与删除验收项。

- [ ] **Step 2: 扫描占位符、旧入口和禁用行为**

Run: `rg -n "TBD|TODO|首页.*导入项目备份|captureLocationHint|deletePublishedImage" README.md docs lib test`

Expected: 没有本计划新增的占位符；不存在首页恢复入口和固定定位提示；项目删除服务不调用 `deletePublishedImage`。

- [ ] **Step 3: 运行格式和静态检查**

Run: `dart format --output=none --set-exit-if-changed lib test integration_test`

Run: `flutter analyze`

Expected: 两项退出码 0，analyze 显示 `No issues found!`。

- [ ] **Step 4: 运行全部 Flutter 与 Rust 测试**

Run: `flutter test`

Run: `cargo fmt --manifest-path rust/Cargo.toml --check`

Run: `cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings`

Run: `cargo test --manifest-path rust/Cargo.toml`

Expected: 全部 PASS，无失败和 clippy 警告。

- [ ] **Step 5: 运行 Android 测试并构建 APK**

Run: `./android/gradlew -p android :sitemark_system_api:testDebugUnitTest`

Run: `flutter build apk --debug`

Expected: Android `BUILD SUCCESSFUL`，APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 6: 检查差异和工作区**

Run: `git diff --check`

Run: `git status --short`

Expected: 无空白错误；只包含本计划范围内文件。

- [ ] **Step 7: 提交文档**

```bash
git add README.md docs/release-checklist.md
git commit -m "docs: explain backup and project deletion behavior"
```

- [ ] **Step 8: 最终审查门**

逐项核对设计文档的自动化测试清单，并审查：bundle ZIP 路径安全、哈希与大小限制；整包回滚标记的崩溃窗口；删除服务不触碰系统相册；重命名不修改历史证据字段；定位授权只由用户主动触发。所有问题修复并重跑相关测试后，才允许推送 PR。

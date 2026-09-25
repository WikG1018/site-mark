# 鸿蒙 NAS 双向同步细化设计（H5）

> 日期：2026-09-26。父设计：`2026-09-25-ohos-alignment-design.md` H5。
> 对齐源：Android #164（双向导入/删除同步）+ #162（真实故障可靠性，Rust 侧随共享 staticlib 自动生效）。

## 侦察结论（已核实）

1. **Rust C ABI 无需改动**：`nasList`（`nas_list` 返回 `{projectKey, fileName}[]`）、
   `nasDownload`、`nasDelete` 均已在 `rust/src/ffi/mod.rs` 分发。#164 新增的 trait 方法
   `list_project_files` 仅被 Dart 编排经 FRB 使用，鸿蒙编排走 `nasList` 即等价。
2. **RDB 缺 `syncMode`**：`AppDatabase.ets` 的 NAS 配置表没有 two-way 模式字段，
   需要一次可迁移 schema 变更（参照既有版本迁移惯例，禁止丢数据）。
3. **NasSyncService** 已有串行上传队列 + bridge 注入面（`upload()` 经 bridge），
   双向能力以并列方法加入，不重构队列。

## 语义（严格对齐 Dart `nas_sync_service.dart`）

- **模式**：`uploadOnly`（D-023 原契约，默认）/ `twoWay`。`twoWay` 额外承担：
  恢复缺失照片（按需导入）与本地删除后清理远端副本。
- **导入预览**：`nasList` 列远端 → 只取 `.jpg`（小写比较）→ 文件名去 `.jpg` 得照片编号 →
  按 `projectKey` 分组 → 与本地（含各项目已有编号）对比得「远端独有」候选。
  候选只读不落库；用户勾选项目后执行导入。
- **导入执行**：所选项目本地不存在则建项目（key 冲突按现有建名规则）；逐张
  `nasDownload` 到私有 originals 目录 → RDB 落记录（编号/时间戳从文件名与下载结果推得，
  与 Dart 落库字段一致）→ 触发既有上传队列去重对账（已在本地的不重复上传）。
- **删除同步**：本地删除记录且模式为 `twoWay` 时，对已上传的远端 JPEG 调 `nasDelete`；
  **本地删除绝不因 NAS 失败**（fire-and-forget + 诊断计数，对齐 Dart 注释契约）。
- **Wi-Fi 门**：导入/删除远端操作沿用现有 `wifiOnly` 门（经同一 bridge 检查）。

## 落点（文件级）

| 文件 | 变更 |
|---|---|
| `core/sync/NasSyncBridge`（NasSyncService 内） | 增加 `list/download/delete` 桥方法（走既有 JSON C ABI） |
| `core/sync/NasTwoWayPolicy.ets`（新） | 纯逻辑：候选计算（jpg 过滤/编号解析/分组/本地对比）、删除守卫（模式+已上传判定）。Hypium 全覆盖 |
| `core/sync/NasSyncService.ets` | `previewImport()` / `importProjects(selected)` / `deleteRemoteForCapture(record)`；导入复用串行队列节奏 |
| `data/database/AppDatabase.ets` | NAS 配置表迁移加 `sync_mode`（默认 `upload_only`，老行回填）；host 契约测试同步 |
| `feature/settings/NasSyncScreen.ets` | 模式分段控件（仅上传/双向）+ 「从 NAS 恢复」入口：预览列表、项目勾选、导入按钮与进度文案（中英） |
| `l10n`（AppText tr 对） | 模式说明、恢复流程、失败文案（分类码，不透传底层错误） |
| `docs/…/deltas.md` | NAS 行更新：two-way 语义对齐声明 + 真机验证待补 |

## 非目标

- 不做双向合并/冲突解决（NAS 侧是导出副本，D-023 已锁）。
- 不做后台自动导入（用户显式触发，对齐 Android）。
- 不改 Rust、不改 Dart。

## 测试与门禁

- `NasTwoWayPolicy`：候选计算（含大小写 jpg、非照片文件、同编号已存在）、删除守卫
  （uploadOnly 不删、未上传不删、twoWay+已上传才删）纯函数全覆盖。
- RDB 迁移：host 契约测试加老库升级路径断言（无 sync_mode → 回填 upload_only）。
- 导入/删除编排：bridge 注入 fake，Hypium 断言调用序与失败不阻断本地删除。
- 常规门禁照旧（build-hap -RunTests / host tests / CI 双绿）。
- 模拟器 + 本地 NAS 服务冒烟；真机网络路径结论只登记不冒充。

## 顺序

1. Policy 纯逻辑 + 测试（先行）。
2. RDB 迁移 + 契约测试。
3. bridge 三方法 + service 编排 + 测试。
4. UI（模式切换 + 恢复流）+ l10n。
5. deltas.md + 冒烟记录。

# 全量产品 HAP 与 Android v1.0.8 差距

对照：`main` / Android SiteMark **v1.0.8**（`1.0.8+23`）。本文件只记产品 HAP（`lib/main.dart`）事实，不把审查壳或 `tool/ohos/review` 一次性脚本当产品证据。

## 已接通（模拟器 `SiteMarkPhone602` / hdc `127.0.0.1:5555`）

- 全量 `lib/main.dart` 未签名 HAP 可装可起：隐私门 → 新建项目 → 项目详情 → 拍摄表单 → 全部记录 → 设置 / 关于 → 备份与恢复。
- Drift / sqlite3：same-isolate + musl so + `NativeAssetsManifest.json`；项目可写入。
- `OhosArchiveSaveService` + 宿主 `saveArchive`：picker 优先，失败/取消回退沙箱。
- 降级 `DegradedImagePipeline.export` 写出 schema 5 zip（`manifest.json` + `records.csv`）。0 张照片的 Task13Demo「不包含原图」在沙箱留下 `files/exports/*.zip`，并弹出系统 Document picker。
- 官方测试：`degraded_image_pipeline_test` / `ohos_platform_services_test` / `platform_services_test` 绿灯。

## 未接通 / 不得宣称

- 备份 zip **未证明**写进系统文件管理。本轮只证实沙箱 zip + picker 弹出，没有 picker 成功 dump。
- 恢复导入仍走降级 `readProjectArchive` / `extractArchivePhoto` / `readBundle`，继续 `invalid_data:`。
- 相机未拍成；定位未出坐标；ACL 未证明。
- 水印引擎仍 degraded，无 `ohos-arm64`。
- 系统通知 / 分享 / 外链仍 no-op。
- 无签名 release，无真机回归。

## 水平结论

项目能存；备份能在应用沙箱导出 zip 并弹出保存选择器。拍 / 水印 / 恢复导入 / 系统文件落盘仍未对等 Android v1.0.8。

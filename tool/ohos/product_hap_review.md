# 产品 HAP 模拟器审查

包名 `io.github.wikg1018.sitemark`，版本 `1.0.8+23`。设备：DevEco 模拟器 `SiteMarkPhone602`，hdc `127.0.0.1:5555`。入口：全量 `lib/main.dart` 未签名 HAP。

## 2026-08-19 Tasks 21–24

走查：隐私门 → 新建 Task13Demo → 设置 → 备份与恢复 → 备份项目 → 勾选 Task13Demo → 继续 → 不包含原图。

| 项 | 结果 |
| --- | --- |
| 产品 HAP 重装 | 未签名 HAP 卸载后安装成功，`aa start` 成功 |
| 降级 zip 导出 | 沙箱留下 `files/exports/sitemark-backup-1787112954673-25897fe6-ebae-47bc-9a56-2f2c69d52cae.zip`（1086 bytes） |
| zip 内容 | `manifest.json` `schema_version: 5`，`records.csv` BOM+表头，`photoCount` 0，无 `photos/` |
| `saveArchive` | 弹出系统 Document picker（「保存」「取消」「文件名称」）。**未完成 picker 保存，不得写已进系统文件管理** |
| 官方测试 | `degraded_image_pipeline_test` / `ohos_platform_services_test` / `platform_services_test` 通过 |

根因修复：此前空 `exports` 不是 save 后删文件，而是 `DegradedImagePipeline.export()` 未实现。现已用 `package:archive` + `crypto` 对齐 Rust schema 5。

## 2026-08-19 Tasks 25–27

官方测试闭环，未重编 HAP、未走系统 `FilePicker`。

| 项 | 结果 |
| --- | --- |
| `readProjectArchive` | 可读自己写出的 schema 5 空项目 zip |
| `extractArchivePhoto` | 解出的 JPEG 字节与源文件一致 |
| `readBundle` / `extractBundleEntry` | 可解出内层项目 zip 再读回 |
| selection zip | `invalid_data: Only single-project archives are restorable` |
| 缺失 zip | `not_found:` |
| 官方测试 | `degraded_image_pipeline_test` 14 项通过 |

## 仍禁止写成已完成

- picker 真正写入系统文件
- 产品页选系统 zip 恢复
- 相机拍成 / ACL / `ohos-arm64`
- 签名 release / 真机

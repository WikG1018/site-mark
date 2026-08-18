# AppGallery 提交材料清单

本文件是材料清单，不是过审证明。产品 `ohos/` 宿主已接上，模拟器上跑的是审查壳 `lib/ohos_review_main.dart`，不是全量 `lib/main.dart`。没有真机 / ACL 授权结果。`flutter build hap --release` 和 AGC 截图不作为完成门槛。详见 `tool/ohos/product_hap_review.md`。

当前引擎状态见 `tool/ohos/engine_status.md`：**degraded**。相册在未获 `READ/WRITE_IMAGEVIDEO` ACL 时走系统保存选择器或应用沙箱。**不能称为与 Android SiteMark v1.0.8 全量对等。**

## 勾选

- [ ] 1. 软著 / 应用名称「工程印记」或 AGC 允许的英文 SiteMark
- [ ] 2. 隐私政策 URL 或随包文本，与首次启动弹窗一致（`AppStrings.privacyConsentBody`）
- [ ] 3. 受限相册 ACL 申请表（`ohos.permission.READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO`）
- [x] 4. 权限逐条用途（插件 `packages/sitemark_system_api/ohos` 的 `module.json5` + `string.json`）
  - 相机：拍摄现场原图
  - 定位：水印可选坐标，可在设置关闭
  - 图库读写：把成片写入系统相册并按本条记录替换或删除
- [ ] 5. 2–5 张截图（项目列表、拍摄表、成片、设置、隐私弹窗）
- [x] 6. 发布说明必须写明非全量对等：引擎 `degraded`；相册可能是 picker / 沙箱
- [ ] 7. 签名、包名、versionCode 与 `pubspec.yaml`（`1.0.8+23`）对齐

## AGC 受限相册说明草稿

工程印记（SiteMark）是离线施工水印相机。申请 `READ_IMAGEVIDEO` 与 `WRITE_IMAGEVIDEO` 仅用于：

1. 将本条拍摄生成的水印成片写入系统相册；
2. 同一 `captureId` 再生成 / 再发布时，按发布日记替换本条成片；
3. 用户删除本条记录时，删除对应成片。

不扫描用户其它相册内容，不按文件名检索全库。未获 ACL 时改用系统保存选择器或应用沙箱，成片不进入系统相册。无账号、无云同步、发布包不申请网络权限。

## 构建说明（未验证）

产品 `ohos/` 宿主已在本分支。社区 Flutter 只允许在仓库外使用。不要在 `main` 的 `ci.yml` 安装社区 Flutter。全量入口必须是 `lib/main.dart`，审查壳 `lib/ohos_review_main.dart` 不能当发布物。

```text
"%OHOS_FLUTTER_ROOT%\bin\flutter" build hap --release
```

当前未执行该命令，也未产出可提交的 release HAP。

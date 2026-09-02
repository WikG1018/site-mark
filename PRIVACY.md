# SiteMark Privacy Notice / 隐私说明

## English

SiteMark is designed to work offline. The application does not create an
account, connect to a SiteMark server, display advertising, or include analytics
SDKs.

When the user starts a capture, SiteMark may request foreground location. The
result is stored locally with the engineering record and may be rendered into
the exported image. Location is never requested in the background. A denied,
approximate, or unavailable result does not block photography and is recorded
explicitly.

Original photos and project records are stored in the application's private
storage. Watermarked photos selected for publication are written to the device's
shared `Pictures/SiteMark` collection. Project archives are created only when the
user requests an export and are handed to Android's system share sheet.

The only network surface is the optional, off-by-default NAS sync (decision
D-023): when you configure your own server — WebDAV, SFTP, or SMB — watermarked
photos are uploaded directly to that server, and to no other destination. The
password is stored in the system secure storage (Android Keystore-backed
storage / iOS Keychain / HarmonyOS asset store) and never enters the database,
backups, or diagnostics. SiteMark itself still has no server, no accounts, no
advertising, and no analytics.

Uninstalling SiteMark removes private application data. Watermarked images
already published to shared storage remain until the user deletes them.

## 简体中文

SiteMark 以离线使用为设计前提，不创建账号、不连接 SiteMark 服务器、不展示广告，也不
包含统计 SDK。

用户开始拍摄时，SiteMark 可以申请使用期间的前台定位。定位结果只保存在本机工程记录
中，并可能显示在水印成片上。应用不申请后台定位；拒绝、模糊或暂时无法获取定位均不
阻止拍照，并会在记录中明确标注。

原图和项目记录位于应用私有存储。发布的水印图写入设备共享的 `Pictures/SiteMark`
目录。只有用户主动导出时才会生成项目归档，并交由 Android 系统分享面板处理。

唯一的网络出口是默认关闭的可选 NAS 同步（决策 D-023）：当你配置自己的服务器——
WebDAV、SFTP 或 SMB——水印成片只会直接上传到该服务器，不经过任何其他目的地。
密码保存在系统安全存储（Android Keystore 支撑的存储 / iOS Keychain / 鸿蒙 asset
资产存储），不进入数据库、备份或诊断。SiteMark 自身依旧没有服务器、账号、广告或
统计 SDK。

卸载 SiteMark 会删除应用私有数据；已经发布到共享相册的水印图将保留，直到用户自行
删除。

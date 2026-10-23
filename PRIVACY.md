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

The only network surfaces are the optional, off-by-default NAS sync (decision
D-023), public release checks and user-requested APK downloads (D-025/026/028). NAS sync, when
you configure your own server — WebDAV, SFTP, or SMB — uploads watermarked
photos directly to that server, and to no other destination. Android checks
public release information while the app is open, at most once every 24 hours;
you can disable automatic checks in About, where manual checks remain available.
iOS and HarmonyOS update behavior is unchanged. Checks read the public GitHub release version first,
and in Automatic mode tries one fixed public mirror only if GitHub cannot be
reached. You can switch to Official only or Mirror first. It does not upload
photos, project data, an account, or diagnostics. Downloads and installation
require your action; packages are verified locally before Android asks you to
confirm installation. Automatic checks add no background job or permission.
On Android 17, a LAN NAS also requires the system local-network permission, which
SiteMark requests from the NAS settings screen. The password is stored in the
system secure storage (Android Keystore-backed storage / iOS Keychain /
HarmonyOS asset store) and never enters the database, backups, or diagnostics.
SiteMark itself still has no server, no accounts, no advertising, and no
analytics.

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

网络用于 NAS 同步、公开版本检查及用户主动下载更新。NAS 同步（决策 D-023）默认关闭：当你配置自己的服务器——
WebDAV、SFTP 或 SMB——水印成片只会直接上传到该服务器，不经过任何其他目的地。
安卓版在应用打开/回到前台时每 24 小时最多自动检查一次，可在关于页关闭，手动检查仍可用（D-028）。
iOS/鸿蒙更新方式不变。检查读取 GitHub 公开版本信息；更新来源为自动时连不上才试固定公开镜像，
也可以改成仅官方或优先镜像，不上传照片、项目数据、账号或诊断。失败不会显示已是最新。
不增加后台定时任务或权限；下载与安装需用户操作，校验安装包后仍由系统要求最终确认。
在 Android 17 上，连接局域网 NAS 还需要系统的本地网络权限，SiteMark 会在 NAS
设置页申请。密码保存在系统安全存储（Android Keystore 支撑的存储 / iOS Keychain /
鸿蒙 asset 资产存储），不进入数据库、备份或诊断。SiteMark 自身依旧没有服务器、
账号、广告或统计 SDK。

卸载 SiteMark 会删除应用私有数据；已经发布到共享相册的水印图将保留，直到用户自行
删除。

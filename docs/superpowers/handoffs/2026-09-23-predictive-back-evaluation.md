# Android 预测返回（Predictive Back）评估结论（2026-09-23）

> Phase D 子项。结论：**现阶段不接入** `PredictiveBackPageTransitionsBuilder`；系统返回派发已就绪，转场动画继续走自有 motion 语言。真机验证前不改行为。

## 一、现状盘点

| 项 | 状态 | 位置 |
| --- | --- | --- |
| `targetSdk` | 37（已就绪） | `android/app/build.gradle.kts` |
| `android:enableOnBackInvokedCallback` | `true`（已就绪） | `android/app/src/main/AndroidManifest.xml` |
| Flutter 预测返回 API | 3.44.6 自带 `PredictiveBackPageTransitionsBuilder` / `PredictiveBackFullscreenPageTransitionsBuilder` | `packages/flutter/.../predictive_back_page_transitions_builder.dart` |
| Framework 回调注册 | 已开 `SystemNavigator.setFrameworkHandlesBack(true)` | `lib/navigation/root_navigation_scaffold.dart` |
| 返回拦截 | 多处 `PopScope`（搜索/选择模式/项目详情/恢复流程等） | `lib/features/**` |
| 页面转场 | **Android 走 `CustomTransitionPage`**，iOS 走 `CupertinoPage` | `lib/app.dart` `_sharedAxisPage` / `_projectDetailPage` / `_captureDetailPage` |

注意：Flutter 3.44.6 的 `PageTransitionsTheme` **默认** Android 已是 `PredictiveBackPageTransitionsBuilder`。但本应用 Android 路由几乎全部是 `CustomTransitionPage`，**不经过** `MaterialPageRoute.buildTransitions`，因此该默认值目前对本应用无效。

## 二、不接入的理由

1. **会打掉 Phase A/C 定下的 motion 语言。** 项目详情短裁剪上推、capture 详情 position-only（为 Hero 让路）、shared-axis——这些都是刻意设计，换成系统 Shared Element 预测返回转场等于回退质感升级。
2. **预测返回手势只在 Android U+ 生效。** `minSdk = 31`，仍有一截设备拿不到该体验；为分档体验再分叉两套转场，成本高于收益。
3. **返回语义已经正确。** `enableOnBackInvokedCallback` + `PopScope` 已保证系统返回能取消搜索、退出选择模式、拦截未保存表单；缺的只是「跟手预览上一屏」的动画层，不是功能。
4. **`CustomTransitionPage` 无法直接吃预测返回进度。** 系统预测返回要求转场由 `PredictiveBackPageTransitionsBuilder`（或等价的手势进度绑定）驱动。若要保留自定义转场又跟手，需要自写 `PredictiveBackEvent` → `Animation` 绑定，属于新功能而非配置开关。
5. **真机结论铁律：** 手感/跟手/取消回弹必须 Android 真机（且最好 U+ 与一台 31–33）对照。模拟器/单测不能替代。当前无验证窗口，不宜盲接。

## 三、若未来要接（备忘，非承诺）

1. 为 `_projectDetailPage` / `_captureDetailPage` / `_sharedAxisPage` 各写一个「预测返回进度 → 现有转场曲线」的绑定层，而不是换 builder。
2. 或仅对「无 Hero、无自定义转场」的 settings 子页试用 `PredictiveBackPageTransitionsBuilder`，与主链路转场隔离。
3. 真机验收清单：跟手预览、中途取消回弹、与 `PopScope` 拦截（搜索/选择模式）叠加、reduce-motion 行为、31–33 上的降级路径。
4. 评估通过后再改 `lib/app.dart` 路由；禁止在未真机验证的情况下合入。

## 四、对 Phase E 的影响

无。规范文档应记录：Android 系统返回派发已 opt-in，预测返回**转场**暂不采用，理由见上。MiSans / token 文档不受此项阻塞。

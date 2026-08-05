# SiteMark 动效与玻璃质感增强设计

## 目标

在 PR #32 已修复串帧、建立根分支滑动与单一玻璃 Dock 指示器的基础上，进一步提升：

1. **根分支切换的空间感与反馈强度**（位移 + 轻微 scale）
2. **GlassSurface 与 Dock 指示器的玻璃厚度感**（顶部高光 + 内描边 + 可关闭极淡噪声）

不改变任何业务逻辑、路由结构、保活语义或 reduce-motion 行为。

## 范围

### 包含

- `RootBranchContainer` 滑动幅度提升 + 目标/来源页轻微 scale
- `GlassSurface` 增加顶部线性高光、1px 内描边、`enableNoise` 极淡噪声（默认开启）
- Dock 指示器同步增加顶部高光与内描边，阴影微调
- 对应测试更新与新增结构断言
- 设计文档与实施计划

### 不包含

- 手指横向拖动切页
- 修改 `AppMotion` 时长或主曲线
- 改变 Offstage / HeroMode / TickerMode / IgnorePointer / ExcludeSemantics 语义隔离策略
- 业务逻辑、数据库、版本号、发布操作
- 新第三方依赖

## 根分支滑动（P0）

### 数值

| 项目 | 当前（PR #32） | 新值 |
|------|----------------|------|
| 目标页位移 | `direction * 0.08` | `direction * 0.16` |
| 来源页位移 | `-direction * 0.04` | `-direction * 0.09` |
| 目标页 scale | 无 | `0.94 → 1.0` |
| 来源页 scale | 无 | `1.0 → 0.985` |
| 时长 | `AppMotion.rootSwitch` (240ms) | 保持 |
| 曲线 | `AppMotion.emphasized` | 保持 |

### 实现要点

- 在现有 `FractionalTranslation` 外包一层 `Transform.scale`
- `scale` 与 `translation` 共用同一个 `progress`（`AppMotion.emphasized.transform`）
- 只有 transitioning 时的 from / to 参与位移和 scale
- 继续使用 `ClipRect` 防止越界
- reduce-motion 时仍直接跳到 value = 1，无动画

### 测试要求

- 更新方向断言，检查中间帧 translation 符号与大致幅度
- 新增 scale 中间值断言（目标页 scale < 1.0，来源页 scale < 1.0）
- 继续保留「全部记录 → 项目 → 详情 → 返回」中间帧 records 分支必须 Offstage 的回归测试

## 玻璃质感（P1）

### GlassSurface

在现有实现上增加：

1. **顶部线性高光**  
   - 从顶部向下约 35% 高度  
   - 浅色模式 alpha 约 0.12~0.16，深色模式约 0.08~0.12  
   - 使用 `LinearGradient`

2. **1px 内描边**  
   - `onSurface` 或 `outline`，alpha 约 0.08~0.12  
   - 放在现有 border 内侧

3. **极淡噪声**  
   - 新增参数 `enableNoise`（默认 `true`）  
   - 不引入新依赖  
   - 噪声 opacity 控制在 0.03~0.06，几乎不可见  
   - `enableNoise: false` 或 reduce-motion 时跳过噪声层  
   - 必须在 `ClipRRect` 内部

继续保留：

- `opacity.clamp(0.58, 0.92)`
- 条件 `BackdropFilter`（仅非 reduce-motion）
- 强制 `onSurface` 文字与图标
- `RepaintBoundary`

### Dock 指示器

- 同步增加顶部高光与 1px 内描边
- 阴影在深色模式下可略微加强
- **不**给指示器单独叠加噪声（避免与外层玻璃噪声重复）
- 继续保持无第二层 `BackdropFilter`

### 测试要求

- 断言默认 `GlassSurface` 包含高光与噪声相关结构
- `enableNoise: false` 时噪声层不存在
- Dock 指示器仍只有一个，且子树无额外 `BackdropFilter`

## 文件清单

- `lib/navigation/root_navigation_scaffold.dart`
- `lib/shared/ui/glass_surface.dart`
- `lib/navigation/root_navigation_dock.dart`
- `test/navigation/root_navigation_scaffold_test.dart`
- `test/navigation/root_navigation_dock_test.dart`
- 可能扩展的 GlassSurface 测试
- 本设计文档与后续实施计划

## 成功标准

1. 根分支切换中间帧具备明确方向位移（约 ±0.16）与 scale（目标约 0.94→1.0）
2. 返回路径中间帧 records 分支仍 Offstage
3. GlassSurface 默认带高光 + 内描边 + 噪声；可关闭噪声
4. Dock 指示器唯一、无额外模糊、带高光与内描边
5. `flutter analyze` 与全量测试通过
6. 无版本号变更、无业务逻辑变更、无新依赖

## 风险与缓解

- **滑动幅度过大**：真机感觉突兀 → 数值已选折中，可通过后续微调
- **噪声性能**：已做成极淡 + 可关闭，默认几乎无感知成本
- **与 PR #32 冲突**：本设计基于 #32 head，合并后直接接续

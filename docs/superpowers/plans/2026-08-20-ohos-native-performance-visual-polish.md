# SiteMark 鸿蒙原生版流畅度与视觉完善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **配套设计：** [`docs/superpowers/specs/2026-08-20-ohos-native-performance-visual-polish-design.md`](../specs/2026-08-20-ohos-native-performance-visual-polish-design.md)。本文件只负责把已确认的“克制工程感 + 全局统一 + 流畅度优先”拆成可执行步骤。

**Goal:** 在不增加产品功能、不改变数据库 schema、备份格式、水印算法和媒体生命周期的前提下，把鸿蒙原生 ArkTS 版的项目列表、记录列表、图片详情/全屏、表单、设置和根部 Dock 统一为更克制、清晰、稳定的界面，并消除长列表、全屏图片和根分支切换中的明显内存与卡顿风险。

**Architecture:** UI 继续使用 Stage + ArkTS + ArkUI；数据仍由 `AppDatabase` 和现有业务服务提供。新增三层轻量基础设施：`LazyListDataSource` 负责只创建可见列表节点，`CapturePagedController` 负责 50 条游标分页、单飞和过期结果丢弃，`ScreenStateStore` 负责根分支重建后的搜索/筛选/首个可见索引恢复。全屏图片由数据库按当前照片查询前后各两张，界面最多保留 5 张；图片统一经过解码尺寸策略和稳定占位组件。视觉层只调整 token 与组件，不复制业务规则。

**Tech Stack:** ArkTS 严格模式、ArkUI `List` / `LazyForEach` / `Scroller` / `Swiper` / `sharedTransition`、HarmonyOS API 24（兼容 API 17）、`@kit.AccessibilityKit`、`@kit.BasicServicesKit`、RelationalStore、Hypium、DevEco Studio 6.1.1、PowerShell 7、Python 3（仅压力测试数据库工具）。

---

## Global Constraints

- 工作分支固定为 `agent/ohos-native-performance-polish`，PR base 固定为 `ohos-native`；不得合入或改写 `main`、`ohos`。
- 只修改鸿蒙原生实现、对应测试、构建/压力测试工具和鸿蒙文档；不得修改 Android/Flutter 产品代码。
- 保留 DevEco 自动生成但未跟踪的 `ohos-native/.clang-tidy`、`ohos-native/.clangd`，不得删除、暂存或提交。
- 不增加页面、业务入口、权限、联网、埋点或产品功能；不改数据库版本 14，不改备份/恢复格式，不改水印输出像素。
- 记录查询每页固定 `50`，不得大于 `50`；项目摘要可一次查询，但 UI 必须使用 `LazyForEach`，不得一次创建全部卡片节点。
- 全屏查看器内存窗口最多 `5` 条（当前照片前后各 2 条）；当前图解码长边上限 2048，邻图 1024，列表缩略图不超过 1024。
- 任何异步列表/图片窗口请求都必须有 generation；旧请求返回后不得覆盖新筛选、新项目或新照片的状态。
- API 23 才提供的“减少动画”查询必须先检查 `deviceInfo.sdkApiVersion >= 23`，并用 `try/catch` 回退为 `false`，保证 compatibleSdkVersion 17 可运行。
- 图片解码失败只能保留稳定占位图，不得在图片区域短暂显示“失败”；记录业务状态为 failed 时仍按现有业务语义显示失败原因。
- 所有行为逻辑先写失败测试，再写最小实现；视觉组件没有可行的 Hypium 渲染断言时，以纯策略测试 + HAP 编译 + 模拟器截图走查验收。
- 首次分页、追加页、图片和查看器补窗失败都必须是局部错误并有重试入口；已有成功内容不得因后续失败被清空。
- 每个 Task 完成后提交一次；不得把所有改动压成一个大提交。

## 统一验收口径

| 范围 | 必须达到 |
| --- | --- |
| 项目/记录列表 | `LazyForEach`；记录 50 条分页；快速切换筛选不会回填旧结果；返回根分支恢复搜索、筛选、生命周期和首个可见索引 |
| 图片 | 列表不解码原始全分辨率；详情最多 2048；查看器最多 5 条、相邻预解码 1024；切换和 Hero 结束后不闪“失败” |
| 视觉 | 标题、卡片、输入、设置行和 Dock 使用统一 token；减少无意义胶囊；中英文标题都不截断关键语义 |
| 动效 | 普通模式短促；系统减少动画开启时导航、Dock、Hero 和淡入时长降为 0；不得用动画遮盖加载 |
| 无障碍 | 所有纯图标按钮有可读名称；选中/禁用/危险状态可读；交互热区不小于 44vp |
| 性能回归 | 2,000 条合成记录压力数据下可滚动、筛选、切换根分支；全屏连续左右切换 20 次，窗口始终不超过 5 条 |

---

## Task 1：建立 ArkUI 惰性列表数据源

**Files:**

- Create: `ohos-native/entry/src/main/ets/shared/LazyListDataSource.ets`
- Create: `ohos-native/entry/src/test/LazyListDataSource.test.ets`
- Modify: `ohos-native/entry/src/test/List.test.ets`

- [ ] **Step 1：先写数据源失败测试**

测试必须覆盖：首次 `replace` 发一次 reload、key 顺序不变的再次 `replace` 对各 index 发 change、`appendUnique` 只追加新 key、监听器注销后不再收到事件、传入数组后外部修改不会污染内部快照。

```ts
class RecordingListener implements DataChangeListener {
  reloads: number = 0;
  added: number[] = [];
  changed: number[] = [];
  onDataReloaded(): void { this.reloads += 1; }
  onDataAdded(index: number): void { this.added.push(index); }
  onDataAdd(index: number): void { this.added.push(index); }
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(index: number): void { this.changed.push(index); }
  onDataChange(index: number): void { this.changed.push(index); }
  onDatasetChange(_operations: DataOperation[]): void {}
}

it('replaces then appends only unique keys', 0, () => {
  const source = new LazyListDataSource<string>((value: string): string => value);
  const listener = new RecordingListener();
  source.registerDataChangeListener(listener);
  source.replace(['a', 'b']);
  source.replace(['a', 'b']);
  source.appendUnique(['b', 'c']);
  expect(source.totalCount()).assertEqual(3);
  expect(source.snapshot().join(',')).assertEqual('a,b,c');
  expect(listener.reloads).assertEqual(1);
  expect(listener.changed.join(',')).assertEqual('0,1');
  expect(listener.added.join(',')).assertEqual('2');
});
```

- [ ] **Step 2：把测试注册到总套件并确认先红**

在 `List.test.ets` 添加 import 和调用，然后执行：

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: 编译失败，提示找不到 `LazyListDataSource`；这证明新测试已真正进入 Hypium 套件。

- [ ] **Step 3：实现最小 `IDataSource`**

实现必须复制输入数组、保存监听器、按 key 去重，并对越界 `getData` 抛出明确错误。核心接口如下：

```ts
export class LazyListDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];
  private readonly keyOf: (item: T) => string;

  constructor(keyOf: (item: T) => string) {
    this.keyOf = keyOf;
  }

  totalCount(): number { return this.items.length; }

  getData(index: number): T {
    if (index < 0 || index >= this.items.length) {
      throw new Error('lazy_list_index_out_of_range');
    }
    return this.items[index];
  }

  snapshot(): T[] { return this.items.slice(); }

  replace(values: T[]): void {
    const previousKeys = this.items.map((item: T): string => this.keyOf(item));
    const nextKeys = values.map((item: T): string => this.keyOf(item));
    const sameOrder = previousKeys.length === nextKeys.length &&
      previousKeys.every((key: string, index: number): boolean => key === nextKeys[index]);
    this.items = values.slice();
    if (!sameOrder) {
      for (const listener of this.listeners) listener.onDataReloaded();
      return;
    }
    for (let index = 0; index < this.items.length; index += 1) {
      for (const listener of this.listeners) listener.onDataChange(index);
    }
  }

  appendUnique(values: T[]): void {
    const keys = new Set<string>(this.items.map((item: T): string => this.keyOf(item)));
    for (const value of values) {
      const key = this.keyOf(value);
      if (keys.has(key)) continue;
      const index = this.items.length;
      this.items.push(value);
      keys.add(key);
      for (const listener of this.listeners) listener.onDataAdd(index);
    }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}
```

- [ ] **Step 4：验证转绿并提交**

执行同一构建测试命令。Expected: ArkTS tests 与 debug HAP 均成功，既有测试无回归。

```powershell
git add ohos-native/entry/src/main/ets/shared/LazyListDataSource.ets `
  ohos-native/entry/src/test/LazyListDataSource.test.ets `
  ohos-native/entry/src/test/List.test.ets
git commit -m "perf(ohos): add lazy list data source"
```

---

## Task 2：统一记录分页、单飞和过期结果丢弃

**Files:**

- Create: `ohos-native/entry/src/main/ets/feature/records/CapturePagedController.ets`
- Create: `ohos-native/entry/src/test/CapturePagedController.test.ets`
- Modify: `ohos-native/entry/src/test/List.test.ets`

- [ ] **Step 1：写三个失败场景**

1. `reset(A)` 尚未返回时执行 `reset(B)`，A 后返回也不能覆盖 B。
2. 连续两次 `loadNext()` 只能调用一次 loader。
3. 两页存在重复 id 时，最终数据不重复；下一游标为空后不再请求。
4. 首页失败可重试；追加失败保留已有数据，重试只重做失败页。

测试用可控 Promise，不用真实数据库；CaptureRecord 工厂必须把 `id`、`projectId`、`capturedAt` 和其余必填字段全部显式填充，禁止 `as any`。

- [ ] **Step 2：运行测试确认缺失实现**

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
```

Expected: 只因 `CapturePagedController` 尚不存在而失败。

- [ ] **Step 3：实现控制器及固定页大小**

接口和状态至少如下；`reset` 允许覆盖旧请求，`loadNext` 必须单飞：

```ts
export const CAPTURE_PAGE_SIZE: number = 50;

export interface CapturePageLoader {
  load(filter: CaptureFilter, cursor: CapturePageCursor | null, pageSize: number): Promise<CapturePage>;
}

export class CapturePagedController {
  readonly data: LazyListDataSource<CaptureRecord> =
    new LazyListDataSource<CaptureRecord>((row: CaptureRecord): string => row.id);
  loadingInitial: boolean = false;
  loadingMore: boolean = false;
  hasMore: boolean = true;
  failed: boolean = false;
  private generation: number = 0;
  private cursor: CapturePageCursor | null = null;
  private filter: CaptureFilter = { projectId: '', year: 0, month: 0, day: 0, searchText: '' };
  private readonly loader: CapturePageLoader;
  private readonly changed: () => void;

  constructor(loader: CapturePageLoader, changed: () => void) {
    this.loader = loader;
    this.changed = changed;
  }

  async reset(filter: CaptureFilter): Promise<void> {
    const generation = ++this.generation;
    this.filter = { projectId: filter.projectId, year: filter.year, month: filter.month,
      day: filter.day, searchText: filter.searchText };
    this.cursor = null;
    this.hasMore = true;
    this.failed = false;
    this.loadingInitial = true;
    this.changed();
    await this.fetch(generation, true);
  }

  async loadNext(): Promise<void> {
    if (this.loadingInitial || this.loadingMore || !this.hasMore) return;
    this.loadingMore = true;
    const generation = this.generation;
    this.changed();
    await this.fetch(generation, false);
  }

  invalidate(): void {
    this.generation += 1;
    this.loadingInitial = false;
    this.loadingMore = false;
  }
}
```

`fetch` 的强制顺序：捕获当前 cursor → `loader.load(this.filter, requestCursor, CAPTURE_PAGE_SIZE)` → 先比较 generation → reset 用 `replace`、续页用 `appendUnique` → 写入 nextCursor/hasMore → finally 只清当前 generation 的 loading 标志。异常只置 `failed=true`，不得清掉已有成功页。增加 `retry()`：没有任何数据时重做当前筛选首页；已有数据时使用未推进的 cursor 重做追加页。

- [ ] **Step 4：增加 2,000 条合成记录压力用例**

Fake loader 按 50 条切页；循环 `loadNext` 到 `hasMore=false`。断言：调用 40 次、`totalCount()==2000`、没有重复 id、任何单页请求的 `pageSize==50`。

- [ ] **Step 5：验证并提交**

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
git add ohos-native/entry/src/main/ets/feature/records/CapturePagedController.ets `
  ohos-native/entry/src/test/CapturePagedController.test.ets `
  ohos-native/entry/src/test/List.test.ets
git commit -m "perf(ohos): centralize capture pagination"
```

Expected: 压力用例和全部既有 ArkTS 测试通过。

---

## Task 3：把全屏查看器改成最多 5 张的数据库窗口

**Files:**

- Modify: `ohos-native/entry/src/main/ets/domain/Models.ets`
- Modify: `ohos-native/entry/src/main/ets/data/database/AppDatabase.ets`
- Create: `ohos-native/entry/src/main/ets/feature/records/PhotoViewerWindow.ets`
- Create: `ohos-native/entry/src/test/PhotoViewerWindow.test.ets`
- Modify: `ohos-native/entry/src/test/List.test.ets`

- [ ] **Step 1：先锁定窗口语义**

新增测试覆盖：当前居中时返回前 2 + 当前 + 后 2；位于首尾时窗口自然缩短；快速切换两张照片时旧窗口不得覆盖新窗口；连续移动 20 次时 `rows.length <= 5`。

- [ ] **Step 2：在模型层增加明确返回类型**

```ts
export class CaptureViewerWindow {
  rows: CaptureRecord[];
  currentIndex: number;
  absoluteIndex: number;
  totalCount: number;

  constructor(rows: CaptureRecord[], currentIndex: number, absoluteIndex: number, totalCount: number) {
    this.rows = rows;
    this.currentIndex = currentIndex;
    this.absoluteIndex = absoluteIndex;
    this.totalCount = totalCount;
  }
}
```

- [ ] **Step 3：新增按稳定排序键查邻图的数据库方法**

`AppDatabase.captureViewerWindow(captureId, radius = 2)` 必须先用 `captureById` 取得项目和 `COALESCE(captured_at,created_at)` 排序时间，再执行三类查询：

```sql
-- 更“新”的最近 radius 条；查询后在 ArkTS 层 reverse，再放到当前项前面
SELECT c.*, p.name AS project_name
FROM captures c JOIN projects p ON p.id=c.project_id
WHERE c.project_id=? AND c.status='ready'
  AND (COALESCE(c.captured_at,c.created_at)>?
    OR (COALESCE(c.captured_at,c.created_at)=? AND c.id>?))
ORDER BY COALESCE(c.captured_at,c.created_at) ASC, c.id ASC LIMIT ?;

-- 更“旧”的最近 radius 条
SELECT c.*, p.name AS project_name
FROM captures c JOIN projects p ON p.id=c.project_id
WHERE c.project_id=? AND c.status='ready'
  AND (COALESCE(c.captured_at,c.created_at)<?
    OR (COALESCE(c.captured_at,c.created_at)=? AND c.id<?))
ORDER BY COALESCE(c.captured_at,c.created_at) DESC, c.id DESC LIMIT ?;
```

再用 `COUNT(*)` 计算项目 ready 总数和当前项前面的条数，得到 `absoluteIndex`。不得调用 `listCaptures` 循环读完整项目。

若当前记录不是 ready，或不在 ready 查询结果中，但当前显示路径仍可用，则返回只含当前记录的单图窗口（`currentIndex=0, absoluteIndex=0, totalCount=1`），不能把页面留空。

- [ ] **Step 4：实现带 generation 的窗口控制器**

`PhotoViewerWindowController.loadAround(captureId)` 只接受数据库返回的 `CaptureViewerWindow`；状态更新前比较 generation。移动到窗口第 0/1 或倒数第 1/2 项后，异步以当前 id 重新居中；新窗口提交时必须保持当前 id，并重新计算局部 index。

- [ ] **Step 5：验证并提交**

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
git add ohos-native/entry/src/main/ets/domain/Models.ets `
  ohos-native/entry/src/main/ets/data/database/AppDatabase.ets `
  ohos-native/entry/src/main/ets/feature/records/PhotoViewerWindow.ets `
  ohos-native/entry/src/test/PhotoViewerWindow.test.ets `
  ohos-native/entry/src/test/List.test.ets
git commit -m "perf(ohos): bound photo viewer window"
```

Expected: 20 次移动测试始终不超过 5 条；现有数据库 schema 版本保持 14。

---

## Task 4：统一图片解码、稳定占位、页面状态和减少动画

**Files:**

- Create: `ohos-native/entry/src/main/ets/shared/AppImage.ets`
- Create: `ohos-native/entry/src/main/ets/shared/MotionPolicy.ets`
- Create: `ohos-native/entry/src/main/ets/shared/ScreenStateStore.ets`
- Create: `ohos-native/entry/src/main/ets/shared/UiMemoryCoordinator.ets`
- Create: `ohos-native/entry/src/test/UiPolicy.test.ets`
- Modify: `ohos-native/entry/src/main/ets/app/AppRuntime.ets`
- Modify: `ohos-native/entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `ohos-native/entry/src/test/List.test.ets`

- [ ] **Step 1：先写纯策略失败测试**

断言：缩略图解码边长始终在 256–1024；详情不超过 2048；查看器当前 2048、相邻 1024；reduce-motion 时所有时长和实时模糊值为 0；每个项目详情状态缓存最多 8 项，超出后淘汰最旧项；内存压力广播即使一个监听器抛错也会继续通知其余监听器。

- [ ] **Step 2：实现图片解码策略和稳定占位组件**

```ts
export class ImageDecodePolicy {
  static thumbnail(edgeVp: number, density: number): number {
    return Math.min(1024, Math.max(256, Math.ceil(edgeVp * density)));
  }
  static detail(): number { return 2048; }
  static viewer(current: boolean): number { return current ? 2048 : 1024; }
}

@Component
export struct AppImage {
  @Prop uri: string = '';
  @Prop decodeEdge: number = 512;
  @Prop fit: ImageFit = ImageFit.Cover;
  @State private loaded: boolean = false;
  @State private failed: boolean = false;

  build() {
    Stack() {
      Row()
        .width('100%').height('100%')
        .backgroundColor(UiTokens.IMAGE_PLACEHOLDER)
      if (this.uri.length > 0 && !this.failed) {
        Image(this.uri)
          .width('100%').height('100%')
          .objectFit(this.fit)
          .sourceSize({ width: this.decodeEdge, height: this.decodeEdge })
          .opacity(this.loaded ? 1 : 0)
          .animation({ duration: MotionPolicy.duration(90), curve: Curve.EaseOut })
          .onComplete((): void => { this.loaded = true; this.failed = false; })
          .onError((): void => { this.loaded = false; this.failed = true; })
      }
      if (this.failed) {
        Button('↻')
          .width(44).height(44)
          .fontSize(22)
          .fontColor(UiTokens.TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .accessibilityText(tr('重新加载图片', 'Reload image'))
          .onClick((): void => { this.failed = false; this.loaded = false; })
      }
    }
    .clip(true)
  }
}
```

`AppImage` 不显示错误文字；失败时只显示可点击、可朗读的重试图标，并通过条件移除/重新创建 `Image` 触发同 URI 重试。调用方负责把 `imageUri(path)` 结果传入。Hero/shared transition 放在外层稳定容器上，以 `capture-photo-${capture.id}` 为唯一 tag。

- [ ] **Step 3：实现 API 17 安全的减少动画策略**

```ts
import { accessibility } from '@kit.AccessibilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';

export class MotionPolicy {
  static reduceMotion: boolean = false;

  static async refresh(): Promise<void> {
    if (deviceInfo.sdkApiVersion < 23) {
      MotionPolicy.reduceMotion = false;
      return;
    }
    try {
      MotionPolicy.reduceMotion = await accessibility.isAnimationReduceEnabled();
    } catch (_) {
      MotionPolicy.reduceMotion = false;
    }
  }

  static duration(normal: number): number {
    return MotionPolicy.reduceMotion ? 0 : normal;
  }

  static blur(normal: number): number {
    return MotionPolicy.reduceMotion ? 0 : normal;
  }
}
```

- [ ] **Step 4：建立根分支/项目详情状态缓存**

`ScreenStateStore` 保存：项目页每个 lifecycle 的 `searchText + firstVisibleIndex`；全部记录的 `CaptureFilter + filterOpen + firstVisibleIndex`；项目详情按 projectId 保存 `CaptureFilter + firstVisibleIndex`。缓存只在内存，不写数据库；项目详情使用最多 8 项的 LRU，避免长期增长。

`UiMemoryCoordinator` 使用独立监听器列表。`EntryAbility.onMemoryLevel(level: AbilityConstant.MemoryLevel)` 只向它广播，不停止 `SerialCaptureQueue`。全屏查看器收到压力后把窗口收缩到当前 1 张；不可见列表收到压力后执行 `invalidate + replace([])`，下次出现按 `ScreenStateStore` 重载；本轮不新增应用级图片缓存。

- [ ] **Step 5：挂到 `AppRuntime` 并验证**

`AppRuntime` 增加只读 `screenState` 和 `uiMemory`；初始化完成后 `await MotionPolicy.refresh()`。不得让减少动画查询失败阻断数据库、恢复或主界面初始化。

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
git add ohos-native/entry/src/main/ets/shared/AppImage.ets `
  ohos-native/entry/src/main/ets/shared/MotionPolicy.ets `
  ohos-native/entry/src/main/ets/shared/ScreenStateStore.ets `
  ohos-native/entry/src/main/ets/shared/UiMemoryCoordinator.ets `
  ohos-native/entry/src/main/ets/app/AppRuntime.ets `
  ohos-native/entry/src/main/ets/entryability/EntryAbility.ets `
  ohos-native/entry/src/test/UiPolicy.test.ets `
  ohos-native/entry/src/test/List.test.ets
git commit -m "feat(ohos): add image motion and screen policies"
```

---

## Task 5：建立“克制工程感”视觉基础组件

**Files:**

- Modify: `ohos-native/entry/src/main/ets/shared/UiTokens.ets`
- Modify: `ohos-native/entry/src/main/ets/shared/AppComponents.ets`
- Create: `ohos-native/entry/src/main/ets/shared/FormComponents.ets`
- Create: `ohos-native/entry/src/main/ets/feature/projects/ProjectComponents.ets`

- [ ] **Step 1：收紧全局尺寸和层级 token**

新增并全局使用下列 token；暗色模式提供对应颜色，不能在页面里散落新的十六进制色值：

```ts
static readonly PAGE_PADDING: number = 16;
static readonly CARD_RADIUS: number = 18;
static readonly CONTROL_RADIUS: number = 12;
static readonly TOP_BAR_HEIGHT: number = 68;
static readonly TOUCH_TARGET: number = 44;
static readonly DOCK_HEIGHT: number = 64;
static readonly MOTION_FAST: number = 120;
static readonly MOTION_STANDARD: number = 180;
static IMAGE_PLACEHOLDER: string = '#E8EEE9';
static SURFACE_MUTED: string = '#EEF4F0';
static OUTLINE_SUBTLE: string = '#D9E3DC';
```

- [ ] **Step 2：重写公共标题栏和设置行**

`AppTopBar`：主标题 24sp、英文允许两行或根据长度降到 22sp，栏高 68vp；返回和操作按钮热区 44vp；纯图标必须传 `accessibilityText`。`SettingRow`：高度按内容最小 64vp，不用整行胶囊背景；标题 16sp、说明 13sp，分隔线只在组内使用。

同时在 `AppComponents.ets` 提供 `AppSearchField`、`LifecycleSegment`、`FilterToolbar`、`BatchActionBar`、`InlineErrorPanel`。这些组件只接收显示值和回调，不读取数据库或 `AppRuntime`；分页首次失败、追加失败和查看器补窗失败统一使用 `InlineErrorPanel`，但文案和重试动作由页面传入。

- [ ] **Step 3：新增可见边界的表单组件**

`FormField`/`FormTextArea` 必须始终显示字段标题、输入底色和 1vp 边界；必填星号、错误文字和帮助文字位置固定，避免焦点变化造成布局跳动。示例结构：

```ts
@Component
export struct FormFieldShell {
  @Prop label: string = '';
  @Prop required: boolean = false;
  @Prop error: string = '';
  @BuilderParam content: () => void = (): void => {};

  build() {
    Column({ space: 7 }) {
      Row({ space: 3 }) {
        Text(this.label).fontSize(13).fontWeight(FontWeight.Medium).fontColor(UiTokens.TEXT_SECONDARY)
        if (this.required) Text('*').fontSize(13).fontColor(UiTokens.DANGER)
      }.width('100%')
      this.content()
      if (this.error.length > 0) {
        Text(this.error).fontSize(12).fontColor(UiTokens.DANGER).width('100%')
      }
    }.width('100%')
  }
}
```

- [ ] **Step 4：抽出项目卡片**

`ProjectCard` 只保留：项目名、生命周期/置顶状态、记录摘要、最多 3 张 56vp 预览。卡片使用普通 surface + 细边界 + 轻阴影；只有生命周期状态使用小型状态标识，整张卡和普通操作不再反复使用胶囊。

- [ ] **Step 5：编译验收并提交**

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
git add ohos-native/entry/src/main/ets/shared/UiTokens.ets `
  ohos-native/entry/src/main/ets/shared/AppComponents.ets `
  ohos-native/entry/src/main/ets/shared/FormComponents.ets `
  ohos-native/entry/src/main/ets/feature/projects/ProjectComponents.ets
git commit -m "style(ohos): define restrained engineering UI"
```

Expected: 中英文和暗色资源均编译；没有新增业务行为。

---

## Task 6：改造项目首页和项目详情列表

**Files:**

- Modify: `ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/records/RecordComponents.ets`

- [ ] **Step 1：项目首页改用 `LazyForEach`**

保留 `listProjectSummaries` 的一次查询，但把 `projects: ProjectSummary[] + ForEach` 替换成 `LazyListDataSource<ProjectSummary>`。加载成功调用 `replace`，空态判断使用单独的 `@State projectCount`。

```ts
private readonly projectSource: LazyListDataSource<ProjectSummary> =
  new LazyListDataSource<ProjectSummary>((item: ProjectSummary): string => item.project.id);
private readonly projectScroller: Scroller = new Scroller();

List({ space: 10, scroller: this.projectScroller }) {
  LazyForEach(this.projectSource, (item: ProjectSummary) => {
    ListItem() { ProjectCard({ summary: item, onOpen: (): void => this.openProject(item) }) }
  }, (item: ProjectSummary): string => item.project.id)
}
.cachedCount(4)
```

- [ ] **Step 2：恢复生命周期、搜索和滚动位置**

`aboutToAppear` 从 `AppRuntime.screenState.projects` 恢复；`onScrollIndex` 保存 start；加载完成后用 `Scroller.scrollToIndex(savedIndex, false, ScrollAlign.START)` 恢复。切换 active/completed/archived 时每个状态分别保存索引；改变搜索词时索引归 0。

`aboutToDisappear/aboutToBeDeleted` 必须取消防抖 timer、调用分页控制器 `invalidate()`、注销 runtime/内存监听器；离开后的异步回调只能被 generation 丢弃。

- [ ] **Step 3：项目详情改用共享分页控制器**

删除项目详情自己的 `captures/cursor/loadGeneration/loadingMore`，改用 `CapturePagedController`；`List` 使用 `LazyForEach(controller.data)` 和 `.cachedCount(4)`，`onReachEnd` 只调用 `controller.loadNext()`。刷新时保留已有成功页直到新首页返回，避免先清空造成卡片一闪。首次失败显示页面内 `InlineErrorPanel`；追加失败在列表尾部显示小型重试行，均调用 `controller.retry()`。

- [ ] **Step 4：接入统一缩略图和项目卡片层级**

项目预览使用 `AppImage`，56vp 显示尺寸、解码边长由 `ImageDecodePolicy.thumbnail(56, this.getUIContext().vp2px(1))` 计算。`CaptureCard` 的 112vp 图片同样使用 `AppImage`，外层 Hero 容器保持稳定 capture id；图片区域永远不显示解码错误文字。

- [ ] **Step 5：模拟器走查后提交**

走查：三个生命周期各自滚动后切换再返回；搜索后切到全部记录再返回；进入项目再返回。预期无全量卡片瞬间闪现，搜索和索引恢复正确。

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
git add ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets `
  ohos-native/entry/src/main/ets/feature/records/RecordComponents.ets
git commit -m "perf(ohos): virtualize project capture lists"
```

---

## Task 7：改造全部记录、详情和全屏查看器

**Files:**

- Modify: `ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/records/RecordComponents.ets`
- Create: `ohos-native/entry/src/main/ets/feature/records/PhotoViewerScreen.ets`
- Modify: `ohos-native/entry/src/main/ets/pages/Index.ets`

- [ ] **Step 1：全部记录接入统一分页和状态恢复**

删除重复分页字段和方法，改用 `CapturePagedController`；搜索 250ms 防抖仍保留，但每次防抖只调用 `reset(currentFilter())`。列表改为 `LazyForEach`，缓存 4 个节点。筛选、搜索、展开状态和 firstVisibleIndex 写入 `ScreenStateStore`。首次/追加失败使用同一套 `InlineErrorPanel + controller.retry()`，不能把已有卡片替换为空态。

页面离开或销毁时取消搜索 timer、`controller.invalidate()` 并注销 runtime/内存监听器；重回页面从 `ScreenStateStore` 恢复后重新加载，旧页面结果不得写回。

- [ ] **Step 2：保持批量选择语义不变**

选择、取消全选、导出、再次保存、清原图和删除仍调用现有业务方法；只调整悬浮栏布局。选择态底部保留单层玻璃面板，按钮图标下方显示短文字，不再给每个按钮加独立框选背景；列表 bottom padding 精确等于操作栏实际高度 + 16vp。

- [ ] **Step 3：详情图片使用 2048 上限和稳定 Hero 端点**

列表卡、详情图和全屏图的 Hero tag 都是 `capture-photo-${capture.id}`；详情层先显示同色稳定占位，再淡入 2048 解码图。切换原图/水印图时先保留当前已显示图，目标图 complete 后再替换，避免黑帧或“失败”闪现。

- [ ] **Step 4：全屏查看器接入 5 张窗口**

把 `PhotoViewerScreen` 从 1,000 行以上的 `RecordScreens.ets` 抽到独立文件，并移除现有循环调用 `listCaptures(filter, cursor, 100)` 的全项目加载。新页面使用 `PhotoViewerWindowController`；`Swiper.cachedCount(1)`，当前图片 2048、两侧图片 1024。计数显示 `${absoluteIndex + 1} / ${totalCount}`，不是局部窗口下标。

窗口重心变化时按 capture id 保持当前项：先完成新窗口查询，确认 generation 和当前 id，再替换 rows 并设置局部 index；缩放大于 1 时禁用横滑，换图后 scale 归 1。只有当前照片外层启用 `sharedTransition`，邻图不得创建 Hero 端点。图片节点 key 必须包含 `${capture.id}-${current ? 'full' : 'preview'}`，换图后让旧当前项按 1024 重新创建，保证同时只保留一个 2048 节点。补窗失败保留当前窗口并显示非遮挡式重试按钮。

- [ ] **Step 5：为所有操作补齐无障碍语义**

返回、搜索、筛选、选择、全选、清除筛选、图片、删除等纯图标或组合控件添加 `accessibilityText`；选中项文字包含“已选择”；危险操作 description 明确“永久删除”；热区不低于 44vp。

- [ ] **Step 6：验证 20 次切换并提交**

在模拟器从记录列表 → 详情 → 全屏，连续左右切换 20 次，再返回两级；确认：图片窗口最大 5、当前计数连续、无黑屏/失败闪现、返回后原列表位置不跳。

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
git add ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets `
  ohos-native/entry/src/main/ets/feature/records/RecordComponents.ets `
  ohos-native/entry/src/main/ets/feature/records/PhotoViewerScreen.ets `
  ohos-native/entry/src/main/ets/pages/Index.ets
git commit -m "perf(ohos): polish records and bounded viewer"
```

---

## Task 8：全局统一表单、设置、Dock、动效与无障碍

**Files:**

- Modify: `ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets`
- Modify: `ohos-native/entry/src/main/ets/pages/Index.ets`
- Modify: `ohos-native/entry/src/main/ets/shared/AppText.ets`
- Modify: `ohos-native/entry/src/test/AppText.test.ets`

- [ ] **Step 1：统一项目/拍摄/编辑表单**

新建项目、项目编辑、拍摄表单、记录编辑和水印设置全部用 `FormFieldShell`；输入框高度 48–52vp，边界始终可见，错误在字段下方，不再用大面积空白玻璃块假装输入框。模板建议仍保留，但普通建议项不再全部画成厚胶囊。

- [ ] **Step 2：统一设置二级菜单**

设置首页以分组标题 + 普通 `SettingRow` 组织；关于、外观、备份恢复、存储、诊断二级页使用相同 TopBar、section spacing 和危险区样式。版本、存储大小等只作次要信息，不与主标题争夺层级。备份页的项目多选列表从 `ForEach` 改为 `LazyForEach`，使用稳定 project id 和有限 cachedCount；不改备份业务逻辑。

- [ ] **Step 3：收紧根部悬浮 Dock**

Dock 高度固定 64vp、左右 14vp、底部安全距离 10–12vp；图标和文字组合居中。选中背景是单块半透明材质并随 tab 以 180ms 横移；Dock 本体与页面内容之间不画分割线。列表底部留白用 `UiTokens.DOCK_HEIGHT + 28` 统一计算。

- [ ] **Step 4：全局接入减少动画**

`Index.switchTab`、根内容 transition、Dock 选中背景、Hero、图片淡入都通过 `MotionPolicy.duration`；初始化和重新回到前台时刷新策略。调用 `pathStack.disableAnimation(MotionPolicy.reduceMotion)`，API 12 可用。所有 `backdropBlur` 通过 `MotionPolicy.blur`，减少动画开启后降为不透明 surface；所有非必要时长为 0，但加载占位仍保留。

- [ ] **Step 5：补齐中英文文案测试和可读语义**

把新增字段标题、错误、图片占位的无障碍名称加入 `AppText`；`AppText.test.ets` 对 zh/en 都断言非空。英文长标题必须用缩短译文或允许两行，不能靠裁切隐藏核心含义。

- [ ] **Step 6：四组视觉走查并提交**

模拟器走查矩阵：中文浅色、中文暗色、英文浅色、英文暗色；每组检查项目首页、全部记录、项目详情、拍摄表单、设置首页、图片详情。再把系统字体调到大号检查标题/操作不裁切，并开启系统减少动画复跑根 tab 和图片查看。

```powershell
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
git add ohos-native/entry/src/main/ets/feature/projects/ProjectScreens.ets `
  ohos-native/entry/src/main/ets/feature/records/RecordScreens.ets `
  ohos-native/entry/src/main/ets/feature/settings/SettingsScreens.ets `
  ohos-native/entry/src/main/ets/pages/Index.ets `
  ohos-native/entry/src/main/ets/shared/AppText.ets `
  ohos-native/entry/src/test/AppText.test.ets
git commit -m "style(ohos): apply polished UI globally"
```

---

## Task 9：压力验证、文档、最终审查和 PR

**Files:**

- Create: `tool/ohos-native/seed-performance-db.py`
- Create: `ohos-native/docs/images/performance-polish/01-projects.webp`
- Create: `ohos-native/docs/images/performance-polish/02-records.webp`
- Create: `ohos-native/docs/images/performance-polish/03-capture-form.webp`
- Create: `ohos-native/docs/images/performance-polish/04-settings.webp`
- Modify: `ohos-native/docs/deltas.md`
- Modify: `ohos-native/README.md`

- [ ] **Step 1：增加不进入生产包的压力数据工具**

Python 工具只接受显式 `--database` 和 `--captures`，只修改从模拟器导出的副本；目标数据库名必须是 `sitemark_native.db`。它创建一个“性能回归”项目和 2,000 条 ready 记录，图片路径复用副本中首条可用 ready 记录；没有可用图片时明确失败并提示先拍一张测试照片。提交后执行 `PRAGMA wal_checkpoint(TRUNCATE)`。工具不得被 HAP 引用。

```powershell
python .\tool\ohos-native\seed-performance-db.py `
  --database .\ohos-native\build\perf\sitemark_native.db `
  --captures 2000
```

Expected: 输出 `seeded=2000`，再次执行应先删除同一 fixture project 后重建，结果仍为 2,000，不重复增长。

- [ ] **Step 2：在 DevEco 模拟器执行 2,000 条压力回归**

关闭应用，从 Device File Explorer 导出沙箱 `sitemark_native.db` 到 `ohos-native/build/perf/`，运行上一步工具，再导回原位置后启动应用。依次完成：项目页滚动到底并返回顶部、全部记录连续滚动、快速输入/清空搜索、反复切换三个根 tab 20 次、进入项目再返回、全屏查看连续切换 20 次。

验收：无崩溃、无旧筛选回填、无全部卡片瞬间闪现、列表位置恢复、查看器窗口调试计数不超过 5。用 DevEco Profiler 记录启动稳定值、连续 20 次查看后的峰值、退出查看器并静置 30 秒后的值；允许缓存抖动，但第二轮不得继续同幅度单向增长。测试完成后恢复原数据库备份，不能把合成数据留给用户环境。

- [ ] **Step 3：保存压缩后的关键截图并更新鸿蒙文档**

截图统一宽 1080px、WebP、单张不超过 300KB；README 展示项目/记录两张，其余由链接进入。`deltas.md` 记录：模拟器性能通过的场景、无法替代真机的内存/相机/相册边界、测试日期和 HAP hash；不得写成“已完成真机验证”。

- [ ] **Step 4：执行完整门禁**

```powershell
python -m unittest tool.test_verify_ohos_native_manifest
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --no-default-features --features ohos-native --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml --no-default-features --features ohos-native
flutter analyze
flutter test
pwsh -File .\tool\ohos-native\build-hap.ps1 -SkipRust -RunTests
git diff --check
```

Expected: 全部退出码 0；最后一条 HAP 命令输出非空 `.hap` 路径和 SHA-256。

- [ ] **Step 5：做计划覆盖与占位符自审**

```powershell
rg -n "TODO|FIXME|待实现|临时实现|throw new Error\('not_implemented'" `
  ohos-native/entry/src/main/ets tool/ohos-native
git diff --name-only origin/ohos-native...HEAD
git status --short
```

Expected:

- 第一条没有本轮新增占位符；若命中既有内容，逐项说明且不扩大。
- 变更只在计划列出的鸿蒙代码、测试、工具和文档中。
- `ohos-native/.clang-tidy`、`ohos-native/.clangd` 仍未跟踪且未暂存。
- 对照设计逐项确认：惰性列表、50 条分页、状态恢复、5 图窗口、解码上限、全局视觉、减少动画、无障碍、压力证据均有实现或验证记录。

- [ ] **Step 6：提交文档与压力工具**

```powershell
git add tool/ohos-native/seed-performance-db.py `
  ohos-native/docs/deltas.md ohos-native/README.md `
  ohos-native/docs/images/performance-polish
git commit -m "docs(ohos): record UI performance verification"
```

- [ ] **Step 7：推送并创建只面向 `ohos-native` 的 PR**

```powershell
git push -u origin agent/ohos-native-performance-polish
gh pr create --base ohos-native --head agent/ohos-native-performance-polish `
  --title "perf(ohos): polish native UI and long-list performance" `
  --body-file .superpowers/sdd/ohos-native-performance-polish-pr.md
gh pr view --json url,baseRefName,headRefName,state,statusCheckRollup
```

Expected: `baseRefName` 精确为 `ohos-native`，`headRefName` 为 `agent/ohos-native-performance-polish`；若 base 显示 `main`，立即停止，不合并，先修正 PR base。

---

## 最终完成定义

- 所有新增 Hypium 测试和原 33+ 测试全部通过；不把测试总数写死到产品文档。
- debug HAP 构建成功并记录 SHA-256；Rust/Flutter 共享仓库门禁仍全绿。
- DevEco 模拟器完成 2,000 条记录与 20 次图片切换压力回归；关键页面四组主题/语言走查完成。
- `main`、`ohos` 无提交；PR 只指向 `ohos-native`。
- 没有未解释的临时代码、无界集合、全图解码、过期请求回填或图片错误闪字。
- PR 仍需独立代码审查通过后才能合并；模拟器通过不等于鸿蒙真机性能已确认。

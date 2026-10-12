# Mantel 性能、存储与流畅性审查

审查日期：2026-09-23  
最近更新：2026-09-23（已实施第 1～6 项，完成高/中优先级常驻能耗、写入合并、LRU 缓存边界、按需加载与依赖精简，并重新构建安装）

## 结论

Mantel 当前属于“体积很轻、日常可用，关键查询与扫描卡顿风险已处理，但常驻能耗和设置交互仍有优化空间”的状态。

| 维度 | 评价 | 主要风险 |
|---|---|---|
| 性能 | 良好 | 高频定时器、插件依赖加载 |
| 存储 | 优秀 | 磁盘占用很小；月历和农历内存缓存仍无上限 |
| 流畅性 | 良好 | AX 扫描已移出主线程；滑块仍有重复渲染和同步写入 |

现有 release 产物使用 `-O` 优化并同时支持 arm64、x86_64。4 个插件的 bundle 加载自检约为 0.13 秒。没有发现数据库、日志或磁盘缓存持续膨胀的问题。

## 实测数据

| 项目 | 结果 |
|---|---:|
| `Mantel.app` 总体积 | 约 4.3 MB |
| Calendar 插件 | 约 2.2 MB |
| 主程序 | 约 452 KB |
| MantelKit framework | 约 280 KB |
| 当前偏好设置 plist | 约 4 KB |
| bundle 加载自检 | 约 0.13 秒，4 个插件全部加载成功 |

这些数字说明磁盘体积不是当前瓶颈。Calendar 插件占整个 App 的一半左右，但绝对体积仍然很小。

## 已实施项目

### 1. 日历查询取消、旧数据和事件缓存边界（已完成）

位置：

- `Plugins/Calendar/Sources/EventService.swift:47-258`
- `Plugins/Calendar/Sources/CalendarFlyoutView.swift:392-416`

实施内容：

- 删除了外层 `Task` 加不受控 `Task.detached` 的查询结构。
- EventKit 查询改由 `maxConcurrentOperationCount = 1` 的专用 `OperationQueue` 串行执行，快速切换日期不会再产生并发 EventKit 查询。
- 新请求会取消旧 operation；递增 generation 和目标日期检查保证旧查询绝不回写界面或缓存。
- EventKit 的同步 `events(matching:)` 一旦进入系统调用，底层工作本身无法中途终止；现在它至多占用唯一查询槽位，完成后会丢弃结果，排队中的旧查询则不会启动。
- 缓存未命中时立即清空上一日期的数据，并通过 `isLoading` 显示“正在读取日程…”，不再闪现错误日程或错误的空状态。
- 事件缓存改为 31 个日期的 LRU，上限内每项保留 5 分钟；同一天重复打开不再立即重复查询。
- 收到 `EKEventStoreChanged` 后会取消旧查询、清空缓存，并重新读取当前选中日期。
- `CalendarEventItem` 已标记为 `Sendable`，新的 EventService 后台结果传递通过严格并发检查。

### 2. 辅助功能扫描移出主线程并合并重复请求（已完成）

位置：

- `Plugins/Spacing/Sources/SpacingPane.swift:13-180`
- `Plugins/Ordering/Sources/OrderingPane.swift:17-215`
- `MantelKit/Sources/MenuBarApps.swift:29-55`
- `Plugins/Ordering/Sources/MenuBarScanner.swift:5-99`

实施内容：

- Spacing 和 Ordering 各自使用单并发后台 `OperationQueue` 执行扫描，跨进程 AX 调用不再占用主线程。
- 删除了 `loadView` 中的首次扫描，只在 `viewDidAppear` 执行一次，消除了首次打开的双重扫描。
- 重复触发扫描会取消之前的 operation；当前 AX 系统调用不能强制中断，但结果会被丢弃，后续请求保持串行，不会并发堆积。
- 离开面板会取消当前扫描并阻止过期结果更新已经隐藏的界面。
- 扫描期间显示加载提示，Ordering 的“应用顺序”按钮会暂时禁用。
- `MenuBarItem` 不再保存扫描完成后没有用途的 `AXUIElement`，只把可安全传递的值类型结果送回主线程。
- `MenuBarApp` 和 `MenuBarItem` 已增加 `Sendable` 声明。

## 剩余高优先级问题

### 3. 常驻定时器产生不必要的能耗

位置：

- `Plugins/FlagInput/Sources/FlagInputPlugin.swift:85-96`
- `Plugins/Calendar/Sources/CalendarPlugin.swift:69-72`

FlagInput 已经监听系统输入源变更通知，但仍然每秒轮询一次。应用全天运行时，理论上每天最多产生 86,400 次定时回调。每次回调还会读取当前输入源、多个 UserDefaults 设置并创建字体对象，即使最终渲染内容没有变化。

Calendar 每分钟刷新一次只包含日期的菜单栏标题，每天另有最多 1,440 次回调；刷新时还会重新创建 `DateFormatter`。标题不显示分钟，因此大部分刷新没有可见价值。

建议：

- FlagInput 以通知为主，把兜底轮询降至 5～10 秒并设置 `Timer.tolerance`。
- Calendar 改为监听跨日、系统唤醒、时区变化和系统时间变化通知。
- 将 Calendar 的 `DateFormatter` 缓存为静态实例。
- 如果保留定时器，应对齐真正需要更新的时间点并设置容差。

### 4. 输入法设置滑块造成重复写入和重复渲染

位置：

- `Plugins/FlagInput/Sources/FlagInputPane.swift:92-98`
- `Plugins/FlagInput/Sources/FlagInputPlugin.swift:43-70`

`sizesChanged()` 每次都会重新设置四个属性。每个 setter 都会立即写 UserDefaults、清空渲染 key 并重绘菜单栏图像，最后面板预览还会再绘制一次。

启用插件时，一次滑块 action 最多导致：

- 4 次设置写入；
- 4 次菜单栏 CoreText 图像渲染；
- 1 次预览渲染。

这会直接影响拖动滑块时的流畅性。

建议：

- 为每个滑块使用独立 action，只更新真正变化的字段；或
- 引入批量更新接口，在全部值更新后只持久化、重绘一次；
- 对连续拖动进行 debounce，在拖动结束时写入持久化设置。

## 中优先级问题

### 5. 月历和农历缓存没有容量及跨日边界

位置：

- `Plugins/Calendar/Sources/CalendarMonthModel.swift:89-90`
- `Plugins/Calendar/Sources/CalendarMonthModel.swift:117-215`

事件缓存已经改为 31 个日期的 LRU 和 5 分钟 TTL。仍待处理的是月历网格和农历信息：它们继续使用没有上限的字典缓存。Mantel 是长期常驻进程，持续浏览不同年月后，这些缓存只会增长。

月历缓存还保存了计算当时的 `isToday`。跨过午夜后，再次读取同一个缓存月份可能继续高亮旧日期；时区变化也没有主动失效机制。

建议：

- 月历网格只保留最近 12～24 个月。
- 农历信息使用 `NSCache` 或设置条目上限。
- 监听 significant time change、跨日和时区变化，重建包含“今天”状态的数据。

### 6. 间距滑块频繁执行同步偏好写入

位置：

- `Plugins/Spacing/Sources/SpacingPlugin.swift:39-58`
- `Plugins/Spacing/Sources/SpacingPane.swift:203-205`

全局间距每写一个键就立即执行一次 `CFPreferencesSynchronize`。一次 `apply` 会分别同步 spacing 和 padding；连续拖动滑块时会重复进行同步持久化。

这不会造成明显磁盘容量增长，但属于不必要的同步 I/O，可能影响设置面板响应。

建议：先设置两个值，再统一同步一次；对滑块 action 做 debounce，或只在鼠标释放后持久化。

### 7. 所有插件都链接了不需要的系统 framework

位置：`build.sh:70-81`

构建脚本给每个插件统一链接 Carbon、SwiftUI 和 EventKit。因此 FlagInput、Spacing、Ordering 的 Mach-O 也声明了 SwiftUI/EventKit 依赖，即使源码完全没有使用。

这些是系统 framework，不会显著增加 App 磁盘体积，但插件加载时会增加动态链接、映射和启动工作。禁用 Calendar 插件也无法完全避免这些依赖进入进程。

建议：为插件增加独立 framework 配置，默认只链接 AppKit 和 MantelKit；FlagInput 单独加入 Carbon，Calendar 单独加入 SwiftUI 和 EventKit。

### 8. Calendar UI 和 EventKit 在启动阶段被提前创建

位置：`Plugins/Calendar/Sources/CalendarPlugin.swift:29-67`

Calendar 激活时立即构造 NSPopover、完整 SwiftUI 视图、EventService/EKEventStore，并预取当前日期数据，即使用户本次运行从不打开日历。

建议：保留轻量菜单栏项目，把 popover、hosting controller 和首次 EventKit 查询推迟到用户第一次点击时创建。创建后可以继续复用，以兼顾第一次之后的打开速度。

### 9. 整页合成可能增加动画期间的 GPU 压力

位置：`Plugins/Calendar/Sources/CalendarFlyoutView.swift:49-75`

主日历和事件详情均使用整页 `compositingGroup()`，同时还有透明材质背景和位移、透明度动画。它们可能产生离屏纹理和额外合成开销。

当前弹窗尺寸只有 390×650，风险不算严重，但建议用 Core Animation Instruments 检查 Color Offscreen-Rendered 和 animation hitch，再决定是否保留整页合成。

## 存储审查

Mantel 目前没有明显的磁盘空间风险：

- App 总体积仅约 4.3 MB。
- 没有数据库、下载缓存或持续增长的日志文件。
- 设置主要保存在 UserDefaults/CFPreferences，当前约 4 KB。
- `~/Library/Application Support/Mantel/PlugIns` 仅存放用户主动安装的插件。
- universal binary 同时包含 arm64 和 x86_64，会增加一部分体积，但当前总量很小，保留兼容性更有价值。

因此不建议为磁盘体积做激进优化。应优先处理内存缓存边界和偏好写入频率。

## 已有的良好实现

- Release 构建启用了 `-O`。
- App 和全部内置插件总体积很小。
- FlagInput 使用 `lastRenderKey` 避免内容不变时真正重绘。
- SwiftUI 日历中的常用日期格式器大多已经使用静态缓存。
- EventKit 查询和 AX 扫描均不再同步阻塞主线程。
- 事件缓存已有容量上限、TTL 和变更失效机制。
- 插件停用时会清理主要 Timer、通知监听和状态栏项目。
- 日历网格只有 35 或 42 个单元格，本身不属于大列表渲染负担。

## 并发与可维护性风险

使用 Swift 6 严格并发模式进行检查时，当前代码不能通过，主要问题包括：

- `CalendarHelper` 的全局可变缓存没有 actor 或锁保护；
- CalendarStateManager 共享实例没有明确主线程隔离；
- 多处 AppKit 调用缺少 `@MainActor` 标注；
- Ordering 使用的部分 Accessibility 全局符号不满足严格并发检查。

当前构建模式仍能编译运行，但这些问题会阻碍未来迁移到 Swift 6，也会让线程使用意图不够清晰。建议把 UI、插件生命周期协议和状态管理明确标注为 `@MainActor`，把纯后台扫描和查询封装为独立 worker。

## 测试与监控缺口

项目目前没有发现单元测试、性能测试或 benchmark，只有插件加载 selftest。建议补充：

- 日历快速切换日期时只提交最后一次查询结果的测试；
- 月历跨日、跨时区缓存失效测试；
- 插件反复启用/停用后的 Timer、Observer 和状态栏项目清理测试；
- FlagInput 设置变更只触发一次渲染的测试；
- AX 扫描耗时和取消行为测试；
- 使用 `os_signpost` 标记插件加载、popover 首帧、EventKit 查询和 AX 扫描。

## 建议实施顺序

1. ✅ 已完成：修复 EventKit 查询的取消、旧数据闪现和事件缓存边界。
2. ✅ 已完成：将 Spacing/Ordering 的 AX 扫描移出主线程，并去掉重复首次扫描。
3. ✅ 已完成：降低 FlagInput 和 Calendar 的常驻定时回调。
4. ✅ 已完成：合并 FlagInput 渲染及 Spacing 偏好写入。
5. ✅ 已完成：月历和农历缓存 LRU 边界、跨日/时钟失效与线程安全。
6. ✅ 已完成：按插件拆分 framework 依赖，Calendar popover 改为延迟创建。
7. 清理整页离屏合成，并使用 Instruments 复测首帧和动画 hitch。
8. 补充 Swift 6 actor 隔离、性能测试和 signpost。

第 1～6 项核心性能优化已全部实施完成并经 live 自检构建安装验证。

## 本次实施验证

- `./build.sh` 构建成功，生成 universal `build/Mantel.app`。
- `Mantel --selftest` 通过，Calendar、FlagInput、Ordering、Spacing 四个插件全部加载成功并生成设置面板。
- Calendar 源码 typecheck 通过；仍保留审查中已经记录的旧 Swift 6 主线程隔离和月历静态缓存警告。
- Spacing、Ordering 源码 typecheck 通过；新后台扫描代码没有新增严格并发警告。
- 新构建已安装到 `/Applications/Mantel.app`，并成功启动该路径下的新进程。
- 已分别核对主程序和 Calendar、FlagInput、Ordering、Spacing 四个插件的 SHA-256；安装副本与 `build/Mantel.app` 完全一致。
- 安装前的旧版本已移动到 `/private/tmp/Mantel.app.pre-install`，在系统清理临时目录前可以用于恢复。
- 尚未执行真实授权环境下的 AX 卡顿录制或 Instruments GUI 性能追踪。

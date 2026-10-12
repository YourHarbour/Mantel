# Mantel

一个可扩展的 macOS 菜单栏工具，功能都以插件形式提供。

Mantel 本身**不占用顶栏** —— 顶栏上出现的图标都是插件自己放的（比如输入法国旗）。

Dock 图标跟着窗口走：窗口开着时是普通 App（有 Dock 图标、有菜单栏、⌘Q 可用），
点红色 X 关掉窗口后会切成 accessory，**从 Dock 里消失**，但进程不退出、插件继续工作。
最小化不算关闭，和普通 App 一样留在 Dock。要把窗口叫回来，从启动台或聚焦搜索再点一次
Mantel（等同于 `open -a Mantel`）。

实现在 `AppDelegate.openWindow(selecting:)` / `windowClosed()`：在 `.regular` 和 `.accessory`
之间来回切 `NSApp.setActivationPolicy`。

```
Mantel.app
├── Contents/MacOS/Mantel                  宿主：加载插件、菜单、设置窗口
├── Contents/Frameworks/MantelKit.framework 插件 API
└── Contents/PlugIns/
    ├── FlagInput.mantelplugin             输入法国旗
    ├── Spacing.mantelplugin               图标间距
    └── Ordering.mantelplugin              图标排序
```

插件是真正的可加载 bundle（`NSPrincipalClass` + `Bundle.load()`），不是编译进去的模块。
放到 `~/Library/Application Support/Mantel/PlugIns/` 里的第三方插件下次启动会一起加载。

主窗口是左侧栏 + 右面板：「总览」列出所有插件并单独开关，每个插件再贡献自己的一页。
窗口会记住上次停在哪一页。

## 构建 & 安装

第一次先建一个本地签名身份（只需要做一次）：

```bash
./tools/make-signing-identity.sh
```

macOS 把辅助功能之类的权限绑在 App 的**代码签名**上。ad-hoc 签名没有固定身份，每次重新
构建签名都会变，权限就会悄悄失效 —— 系统设置里那一行还打着勾，App 却被告知没有授权。
这个脚本在登录钥匙串里建一个自签名证书，`build.sh` 之后都用它签名，授权就能跨构建保留。
（证书不出本机，也不是什么安全边界，只是让 macOS 认出「这还是上次那个 App」。）

然后：

```bash
./build.sh && cp -R build/Mantel.app /Applications/ && open /Applications/Mantel.app
```

建议放 `/Applications`：登录项和辅助功能授权都跟 App 路径绑定，来回搬会失效。

没有跑过签名脚本也能构建，`build.sh` 会回退到 ad-hoc 并提示一句，只是每次构建后
要重新授权一次辅助功能。

构建完可以自检一遍（不需要图形界面）：

```bash
./build/Mantel.app/Contents/MacOS/Mantel --selftest --live
```

会列出找到的插件、各自的菜单项和设置面板，`--live` 还会激活插件并报告真正建出来的菜单栏图标。

## 插件

### 输入法国旗

菜单栏用国旗 emoji 显示当前输入法，点击可切换。补上苹果后来去掉的那个小国旗。

| 输入法 | 旗帜 | 代码 |
|---|---|---|
| 简体拼音 / 双拼 / 五笔 | 🇨🇳 | CN |
| 繁体拼音 / 注音 / 仓颉 | 🇨🇳 | CN |
| 粤拼 | 🇭🇰 | HK |
| **ABC**（通用英文布局） | **🇦🇺** | **EN** |
| Australian / British / U.S. | 🇦🇺 / 🇬🇧 / 🇺🇸 | EN |
| 日语 / 韩语 / 法语 / 德语 … | 🇯🇵 / 🇰🇷 / 🇫🇷 / 🇩🇪 | JP / KR / FR / DE |

英语一律显示 `EN`，靠旗帜区分澳/英/美。没匹配上的按主语言猜一面旗，再猜不出来显示 ⌨️。
换旗帜：点菜单栏上的旗子 →「…的旗帜」，只影响当前那个输入法。同一个菜单里的
「打开 Mantel…」会把主窗口切到这个插件的面板。

**竖向居中**：`NSStatusItem.attributedTitle` 是按字体行框（ascent + descent）居中的，不是按
字形墨迹，结果整体比其他菜单栏图标高约 1.25pt；旗帜和字母共用基线，emoji 图案又会伸到基线
下方，字母看起来还会更低。所以改成用 CoreText 取 `useGlyphPathBounds`，**每一部分各自独立
居中**再画进 `NSImage`（`MantelKit/Sources/StatusItemRenderer.swift`）。截图像素实测：改之前
旗帜中心偏离菜单栏中心 −2.5px，改之后 +0.5px，和相邻系统图标（0 ~ +1.0px）一致。

**已知限制**：中文输入法内部用 Shift 切的中/英状态，系统层面输入源没变，旗子不会跟着动。
这是 TIS API 的限制，付费的同类软件也一样。

### 图标间距

调 `NSStatusItemSpacing` 和 `NSStatusItemSelectionPadding` 两个隐藏全局设置，控制**所有** App
的状态栏图标各占多宽。

每个 App 是在**创建**自己的状态栏图标那一刻读这两个值的，所以改完只有重新启动的 App 会变；
要全部生效得注销重新登录。面板上的「应用并重启 Mantel」只让 Mantel 自己立刻生效。

### 给每个 App 单独设置

这两个键是通过 CFPreferences 读的，而查找顺序是**先查 App 自己的域，再查全局域**。
所以把它们写进某个 App 自己的域，就能只给那个 App 单独设值：

```bash
defaults write com.bjango.istatmenus.status NSStatusItemSpacing -int 12
defaults write com.bjango.istatmenus.status NSStatusItemSelectionPadding -int 12
```

实测确认（全局设 0、给 Mantel 自己的域写 20，重启后图标左右间距各多了正好 20px）。

面板上的「单独设置」把这件事做成了界面：列出每一个真正拥有菜单栏图标的 App，
每行两个下拉（间距 / 留白），默认「跟随全局」，改成数字就是给这个 App 单独设值。
已经设过、但当前没在运行的 App 也会一并列出来，方便改回去。

用途是这样的：iStat Menus 这类要在图标里画图表和数字的 App，宽度在创建图标时就定死了，
全局留白压太小会把内容裁掉一截。给它单独调回 12 就好，其他图标仍然保持紧凑。

**要挑对进程**：菜单栏图标往往属于 App 的辅助进程而不是主程序 —— iStat 的三个图标归
`com.bjango.istatmenus.status`（显示名「iStat Menus Menubar」）管，写到 `com.bjango.istatmenus`
是没用的。列表是用辅助功能 API 的 `AXExtrasMenuBar` 枚举出来的，只会列真正持有图标的进程，
后面的「N 个图标」就是数量，照着挑不会错。没授权时会退化成列出所有运行中的 App 并给出提示。

这台机器（macOS 26.5）截图实测，Mantel 到右邻图标的墨迹间距：

| 设置 | 间距 |
|---|---|
| 系统默认 | 21pt |
| 间距 2 + 留白 4 | 14pt |
| 全设为 0 | 13pt |

从 2 压到 0 只多省 1pt，却会让点击热区紧贴图标，建议留 4~6。

### 图标排序

两条路，因为 macOS 26 改了菜单栏的实现方式。

**Mantel 自己的图标**（不需要任何权限，已验证可用）：`NSStatusItem` 创建时会从所属 App 自己的
偏好里读 `NSStatusItem Preferred Position <autosaveName>`。Mantel 就是所属 App，所以可以直接
写。数值越小越靠右，但系统当成「偏好位置」而不是精确坐标 —— 实测 100 会顶到最右、600 和 1200
落在同一个槽位，也就是会吸附并在两端截断。按住 ⌘ 拖动顶栏图标时 macOS 也会自己往这里写值。
改完重启 Mantel 生效。

**所有其他 App 的图标**（需要辅助功能权限）：macOS 26 把第三方状态栏图标全部收进了 Control
Centre 进程 —— `CGWindowListCopyWindowInfo` 只会返回几个 owner 是 "Control Centre" 的聚合窗口，
已经识别不出单个图标了。唯一还能逐个拿到的途径是辅助功能 API 的 `AXExtrasMenuBar`，排序则靠
模拟你手动按住 ⌘ 拖图标的动作。Bartender、Ice 也是走的同一条路。

第一次用要在 系统设置 → 隐私与安全性 → 辅助功能 里给 Mantel 打勾。注意 ad-hoc 签名的 App
每次重新构建签名都会变，系统会认为是另一个 App，需要重新授权。

## 写一个插件

插件是一个真正的可加载 bundle：宿主用 `Bundle.load()` 把它载进来，读 `Info.plist` 里的
`NSPrincipalClass`，实例化，然后当作 `MantelPlugin` 使用。宿主不需要知道你的存在，
你也不需要改宿主一行代码。

### 1. 建目录

`Examples/Hello/` 是一个能跑的最小插件，直接复制过去改最快：

```bash
cp -R Examples/Hello Plugins/MyPlugin
```

`build.sh` 会自动发现 `Plugins/` 下的每个文件夹并编译 —— 不用登记到任何清单里。
（`Examples/` 不在扫描范围内，所以模板本身不会被打进 App。）目录长这样：

```
Plugins/Hello/
├── Sources/            所有 .swift 都会被编译
└── Resources/Info.plist
```

### 2. Info.plist

```xml
<key>CFBundleName</key>       <string>Hello</string>
<key>CFBundleExecutable</key> <string>Hello</string>   <!-- 必须和文件夹同名 -->
<key>CFBundleIdentifier</key> <string>com.example.hello</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>NSPrincipalClass</key>   <string>HelloPlugin</string>
```

`NSPrincipalClass` 填的是 **Objective-C 运行时名**。Swift 类默认带模块前缀，所以类上必须写
`@objc(HelloPlugin)`，否则宿主找不到它，会在「总览」页报「Info.plist 里没有 NSPrincipalClass」。

### 3. 写类

```swift
import AppKit
import MantelKit

@objc(HelloPlugin)                       // 名字要和 NSPrincipalClass 对上
public final class HelloPlugin: NSObject, MantelPlugin {

    public static let identifier  = "com.example.hello"   // 设置存储的命名空间，定了就别改
    public static let displayName = "打招呼"               // 侧栏和总览里显示的名字
    public static let summary     = "示例插件。"            // 总览里名字下面那行小字
    public static let symbolName  = "hand.wave"           // 侧栏图标，SF Symbol 名

    private let host: PluginHost
    private let settings: PluginSettings

    public init(host: PluginHost) {
        self.host = host
        self.settings = host.settings(for: HelloPlugin.identifier)
        super.init()
    }

    public func activate() {
        // 需要菜单栏图标就找宿主要一个，不需要就别要。
        let item = host.statusItem(id: "main", for: Self.identifier)
        item.button?.title = "👋"
    }

    public func deactivate() {
        // 用户在总览页关掉插件时调用。宿主会自动回收发给你的状态栏图标，
        // 你只需要收掉自己的 timer、通知监听之类的东西。
        host.removeStatusItem(id: "main", for: Self.identifier)
    }

    public func makePane() -> NSViewController? {
        Pane.viewController(content: Pane.column([
            Pane.header("打招呼"),
            Pane.note("这一页会出现在 Mantel 侧栏里。"),
        ]))
    }
}
```

`activate()` / `deactivate()` 可能被反复调用（用户来回开关），写成幂等的。
`makePane()` 返回 `nil` 的插件不会出现在侧栏里，只在总览页有一行开关。

### 4. 编译、验证

```bash
./build.sh
./build/Mantel.app/Contents/MacOS/Mantel --selftest --live
```

`--selftest` 会用和运行时完全一样的路径加载所有插件，列出成功的、失败的和失败原因；
`--live` 还会激活它们并报告真正建出来的菜单栏图标。不需要图形界面，加载类的问题在这里
就能看出来，不用开着窗口猜。

### 宿主提供的服务

`PluginHost`（见 `MantelKit/Sources/PluginHost.swift`）：

| 方法 | 作用 |
|---|---|
| `statusItem(id:for:)` | 要一个菜单栏图标。同一个 `id` 重复调返回同一个，宿主负责回收 |
| `removeStatusItem(id:for:)` | 提前撤掉某个图标 |
| `settings(for:)` | 按插件隔离的设置存储，见下 |
| `ownedStatusItemNames` | Mantel 名下所有图标的 autosave 名（「图标排序」插件用它定位自己人）|
| `showWindow(selecting:)` | 把主窗口调出来并切到某个插件的面板 |
| `log(_:from:)` | 带插件名前缀的日志 |

### 存设置

`PluginSettings` 是 `UserDefaults` 的薄封装，所有键自动加上插件 id 前缀，两个插件都用
`"style"` 也不会打架：

```swift
var style: String {
    get { settings.string("style", default: "flag") }
    set { settings.set(newValue, for: "style") }
}
```
有 `string / double / int / bool / dictionary / stringArray` 几种读法，都要求传默认值。

### 拼面板

`MantelKit/Sources/PreferencePane.swift` 里有一套控件，各插件用同一套才能长得像一个 App：

| | |
|---|---|
| `Pane.header(_:)` | 小节标题 |
| `Pane.label(_:)` / `Pane.note(_:)` | 正文 / 次要说明（灰色小字）|
| `Pane.row(_:_:)` | 左标题右控件的一行 |
| `Pane.column(_:)` | 纵向排列 |
| `Pane.spacer(_:)` | 小节之间的间隔 |
| `Pane.stretch(_:in:)` | 让某个视图撑满整列宽度 |
| `Card(content:)` | 圆角浅底的卡片，跟随明暗模式 |
| `Pane.viewController(content:)` | 套上边距和滚动视图，返回可以直接给 `makePane()` 的控制器 |

画菜单栏文字用 `StatusItemRenderer.image(_:appearance:gap:padding:verticalOffset:)`，
它会按字形墨迹逐段居中 —— 直接用 `NSStatusItem.attributedTitle` 的话会比别的图标高约 1.25pt。

### 装到别处

`build.sh` 会把 `Plugins/` 下的东西打进 `Mantel.app/Contents/PlugIns`。不想动 app bundle
的话，把编译好的 `.mantelplugin` 放进这里也一样会加载：

```
~/Library/Application Support/Mantel/PlugIns/
```

（总览页的「打开插件文件夹」按钮就是开这个目录。）改完插件要重启 Mantel 才会重新加载。

### 一个警告

插件和宿主跑在同一个进程里，没有沙盒隔离 —— 插件崩溃会带着整个 Mantel 一起崩。
这是为了让插件能直接操作 `NSStatusItem` 和 `NSViewController` 而做的取舍。

## 目录

```
MantelKit/     插件 API：MantelPlugin 协议、PluginHost、PluginSettings、
               StatusItemRenderer（墨迹居中渲染）、Pane / Card（面板控件）、
               MenuBarApps（查询哪些 App 拥有菜单栏图标、读写它们的偏好）
Host/          宿主 App：插件发现与加载、主窗口（侧栏 + 面板）、应用菜单
Plugins/       三个插件，各自独立编译成 .mantelplugin
Examples/      可以直接复制的最小插件模板（不参与构建）
tools/         make-icon 用 CoreGraphics 画 App 图标；make-signing-identity 建本地签名证书
build.sh       swiftc 直接构建：framework + host + 全部插件，universal + ad-hoc 签名
```

## 名字和图标

Mantel 是「壁炉架」（mantelpiece）—— 壁炉上方那块横板，专门用来摆放和陈列东西。
菜单栏就是这么一块横着的架子，图标都摆在上面，而这个 App 管的就是架子上东西怎么摆。
图标画的正是这个：一块横板，上面立着三件陈列品。

图标是代码画的，不是图片资源。改配色或形状就编辑 `tools/make-icon.swift`，然后
`./tools/make-icon.sh && ./build.sh`。

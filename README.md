# CodexPlus

CodexPlus 是一个 macOS 菜单栏 App，用来近实时显示 Codex 桌面端的使用用量。

第一阶段目标刻意保持很小：先把 Codex 桌面端的当前用量稳定显示在苹果状态栏上；后续再扩展到每日汇总、预算、提醒和历史图表。

## 已确认决策

- 第一版数据源：Codex 桌面端用量。
- token 用量来源：Codex 桌面端本身暴露或记录的用量数据。
- 最低系统版本：macOS 26。
- 状态栏显示内容：用户可以自定义配置选择。
- 产品定位：面向分发的 macOS App。

## 产品想法

使用 Codex 时，用量很容易在工作流里被忽略。CodexPlus 要做的是让它一眼可见：

- 状态栏文字：用户可配置显示当前会话 token、今日 token、预估花费或剩余额度。
- 弹窗面板：显示更完整的用量、最近会话、刷新状态和提醒。
- 阈值提醒：当用量超过配置阈值时，可选发送 macOS 通知。
- 隐私优先：默认只在本地处理数据；任何联网数据源都需要用户明确开启。

## MVP 目标

MVP 只先回答一个问题：

> “我现在已经用了多少 Codex？”

初始功能：

- 一个没有 Dock 图标的 macOS 菜单栏 App。
- 状态栏显示用户选择的紧凑指标，例如 `12.4K` 或 `68%`。
- 弹窗面板显示：
  - 当前会话用量，
  - 今日总用量，
  - 上次更新时间，
  - 当前数据源，
  - 刷新和退出操作。
- 抽象出用量数据提供器；第一版接入 Codex 桌面端用量，开发期保留 Mock 数据源便于 UI 和状态测试。
- 尽可能通过文件监听实现近实时更新，必要时退回轮询。

## 数据源策略

这个项目最大的风险不是菜单栏 UI，而是 Codex 用量的真实来源。

第一版明确以 Codex 桌面端用量作为唯一真实数据源。实现上仍然建议先定义一个内部统一模型，让 UI 不直接依赖具体解析方式：

```text
UsageProvider
  -> CodexDesktopUsageProvider
  -> MockUsageProvider
```

建议的统一数据模型：

```text
UsageSnapshot
  sessionId
  providerName
  updatedAt
  inputTokens
  outputTokens
  cachedInputTokens
  reasoningTokens
  totalTokens
  todayTotalTokens
  estimatedCost
  budgetLimitTokens
```

第一版实现围绕 `MockUsageProvider` 和 `CodexDesktopUsageProvider` 来做。`MockUsageProvider` 用于开发和测试，`CodexDesktopUsageProvider` 默认读取 Codex 桌面端的真实用量。真实数据源细节见 [Codex 桌面端用量数据源](docs/codex-desktop-usage-source.md)。

## 技术方向

推荐技术栈：

- Swift + SwiftUI。
- 最低支持 macOS 26，优先使用系统最新 SwiftUI 能力。
- 使用 `MenuBarExtra` 构建菜单栏入口。
- 使用 `ObservableObject` 或 Observation 管理 UI 状态。
- 本地文件数据源优先考虑 `FileSystemEventStream` 或 `DispatchSourceFileSystemObject` 做监听。
- 轻量设置使用 `UserDefaults`。
- 面向分发构建，优先使用 Xcode 项目管理签名、资源和发布配置。

当前脚手架：

- `CodexPlus.xcodeproj`：macOS App 工程。
- `CodexPlus/CodexPlusApp.swift`：SwiftUI App 入口和 `MenuBarExtra` 配置。
- `CodexPlus/MenuBarContentView.swift`：菜单栏弹窗 UI 和占位用量数据。
- `CodexPlus/Models/MenuBarDisplayMode.swift`：状态栏显示模式，包括当前会话、今日用量、预算比例和预估花费。
- `CodexPlus/Models/UsageSnapshot.swift`：统一用量快照模型和显示格式化工具。
- `CodexPlus/Providers/CodexDesktopUsageProvider.swift`：读取 Codex 桌面端 SQLite 日志的真实用量 provider。
- `CodexPlus/Providers/CodexUsageLogParser.swift`：解析 `response.completed` usage JSON 的日志解析器。
- `CodexPlus/Providers/UsageProvider.swift`：用量数据源协议和 provider 错误类型。
- `CodexPlus/Providers/MockUsageProvider.swift`：开发期 Mock 数据源。
- `CodexPlus/Services/UsageService.swift`：负责刷新、文件监听、轮询、错误状态和数据过期状态。
- `CodexPlus/Settings/SettingsStore.swift`：用户设置存储，目前用于持久化状态栏显示模式。
- `CodexPlus/Info.plist`：App 元信息，包含 `LSUIElement`，用于隐藏 Dock 图标。

高层架构：

```text
CodexPlusApp
  -> MenuBarContentView
  -> SettingsStore
  -> UsageService
  -> UsageProvider
  -> MockUsageProvider
```

## 菜单栏体验

这个 App 应该像一个安静的工具，而不是被挤进菜单栏的小型仪表盘。

状态栏显示项由用户配置选择，第一版可支持：

- 今日总 token，
- 当前会话 token，
- 每日预算百分比，
- 今日预估花费。

当前 UI MVP 已支持在菜单栏弹窗中切换状态栏显示模式，选择会写入 `UserDefaults`，重启后保留。弹窗中同时展示当前会话总 token、今日总 token、输入/输出/缓存输入/推理 token 明细、预算比例、预估花费、数据源、更新时间和手动刷新操作。

弹窗面板区域：

- 当前会话。
- 今日用量。
- 预算。
- 数据源健康状态。
- 设置。

状态类型：

- 正常：用量正在更新。
- 过期：超过配置时间没有收到新数据。
- 警告：超过预算阈值。
- 错误：数据源失败或找不到用量来源。

## 隐私与安全

原则：

- 默认不把用量数据发送到任何地方。
- 优先解析本地数据，而不是请求网络接口。
- 如果后续加入 API 数据源，API Key 必须存入 Keychain。
- 在弹窗中清楚显示当前启用的数据源。
- 把路径和日志都视为可能包含敏感信息的数据。

## 开发说明

当前仓库已经包含一个最小 macOS 菜单栏 App 脚手架。它使用 `UsageService` 驱动状态栏文字和弹窗内容，默认 provider 是 Codex 桌面端真实用量数据源。

默认运行时已经使用 `CodexDesktopUsageProvider` 读取 Codex 桌面端真实用量；`MockUsageProvider` 继续保留用于开发、预览和后续测试。

本地运行：

1. 使用 Xcode 打开 `CodexPlus.xcodeproj`。
2. 选择 `CodexPlus` scheme。
3. 运行 App 后，它会出现在 macOS 菜单栏，不显示 Dock 图标。

命令行构建需要完整 Xcode 和 macOS 26 SDK。当前如果只安装 Command Line Tools，`xcodebuild` 无法构建这个 App。

## 后续待确认问题

- 是否需要按 Codex 会话、项目或工作区拆分用量？
- 状态栏显示项的默认值应该是什么？
- 面向分发时采用哪种签名、打包和更新机制？

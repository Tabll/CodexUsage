# CodexPlus

CodexPlus 是一个 macOS 菜单栏 App，用来近实时显示 Codex 的使用用量。

第一阶段目标刻意保持很小：先把当前 Codex 会话的用量稳定显示在苹果状态栏上；等用量数据源确认稳定后，再扩展到每日汇总、预算、提醒和历史图表。

## 产品想法

使用 Codex 时，用量很容易在工作流里被忽略。CodexPlus 要做的是让它一眼可见：

- 状态栏文字：显示当前会话 token、当日花费或剩余额度。
- 弹窗面板：显示更完整的用量、最近会话、刷新状态和提醒。
- 阈值提醒：当用量超过配置阈值时，可选发送 macOS 通知。
- 隐私优先：默认只在本地处理数据；任何联网数据源都需要用户明确开启。

## MVP 目标

MVP 只先回答一个问题：

> “我现在已经用了多少 Codex？”

初始功能：

- 一个没有 Dock 图标的 macOS 菜单栏 App。
- 状态栏显示紧凑指标，例如 `12.4K` 或 `68%`。
- 弹窗面板显示：
  - 当前会话用量，
  - 今日总用量，
  - 上次更新时间，
  - 当前数据源，
  - 刷新和退出操作。
- 抽象出用量数据提供器，后续可以切换本地日志、文件导出、Mock 数据或 API 数据源。
- 尽可能通过文件监听实现近实时更新，必要时退回轮询。

## 数据源策略

这个项目最大的风险不是菜单栏 UI，而是 Codex 用量的真实来源。

CodexPlus 不应该一开始就把某一种脆弱假设写死。建议先定义一个内部统一模型，再让不同适配器来喂数据：

```text
UsageProvider
  -> CodexLocalLogProvider
  -> CodexSessionFileProvider
  -> OpenAIUsageApiProvider
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
  estimatedCost
  budgetLimit
```

第一版实现建议先围绕 `MockUsageProvider` 和一个本地文件数据源来做。这样即使真实 Codex 用量来源后面调整，App 的 UI 和状态管理也能先稳定下来。

## 技术方向

推荐技术栈：

- Swift + SwiftUI。
- macOS 13+ 使用 `MenuBarExtra`。
- 如果需要支持更老系统，再考虑 `NSStatusItem` 兜底。
- 使用 `ObservableObject` 或 Observation 管理 UI 状态。
- 本地文件数据源优先考虑 `FileSystemEventStream` 或 `DispatchSourceFileSystemObject` 做监听。
- 轻量设置使用 `UserDefaults`。
- 第一版优先用 Swift Package Manager；当签名、资源、发布流程需要时再迁移到 Xcode 项目。

高层架构：

```text
CodexPlusApp
  -> MenuBarView
  -> UsageViewModel
  -> UsageService
  -> UsageProvider
  -> SettingsStore
```

## 菜单栏体验

这个 App 应该像一个安静的工具，而不是被挤进菜单栏的小型仪表盘。

默认状态栏显示项可以支持：

- 今日总 token，
- 当前会话 token，
- 每日预算百分比，
- 今日预估花费。

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

当前仓库是空项目。下一步可以先搭一个最小 macOS 菜单栏 App，然后把 UI 接到 Mock 数据源上，最后再接入真实 Codex 用量数据。

在写正式解析逻辑之前，需要先检查当前环境里 Codex 实际暴露了什么用量信息，并决定第一个真实数据源应该读取：

- Codex 会话日志，
- 导出的用量 JSON，
- OpenAI 用量 API，
- 或者由 CodexPlus 自己维护的辅助脚本。

## 待确认问题

- 第一版应该优先追踪哪个 Codex 使用场景：Codex 桌面端、Codex CLI、OpenAI API 用量，还是全部？
- 本地最可靠的 token 用量来源是什么？
- 状态栏默认应该显示 token、预估花费，还是剩余额度？
- 最低支持哪个 macOS 版本？
- 这个项目先做成开发者本地工具，还是一开始就按可分发 App 来准备？

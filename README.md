# CodexPlus

CodexPlus 是一个 macOS 菜单栏 App，用来近实时显示 Codex 桌面端的用量与剩余额度。

当前版本：`0.1.0 (1)`
最低系统：macOS 26
产品定位：面向分发的本地优先 App

## 当前状态

CodexPlus 已完成 MVP 到打包发布阶段：

- 默认读取 Codex 桌面端本地用量日志，不请求 Codex 接口。
- 状态栏默认显示 `5小时 x% 本周 x%`，用于快速查看 5 小时额度和每周额度。
- 菜单栏弹窗保持轻量，只展示核心用量概览、刷新、设置和退出。
- 预算、提醒、数据源和状态栏显示项放在独立设置窗口中。
- 已支持 Developer ID 签名、公证和 stapled 分发包。

## 功能

- 菜单栏文字显示：
  - `5小时 x% 本周 x%`
  - 当前会话 token
  - 今日 token
  - 5 小时剩余百分比
  - 每周剩余百分比
  - 每日预算百分比
  - 今日预估花费
- 菜单栏弹窗：
  - 5 小时剩余额度和刷新时间
  - 每周剩余额度和刷新时间
  - 今日用量
  - 当前会话用量
  - 数据源状态
  - 最近更新时间
  - 手动刷新、打开设置、退出
- 设置窗口：
  - 状态栏显示内容
  - 数据源选择
  - 每日预算
  - 警告阈值
  - macOS 通知开关
- 数据能力：
  - 解析 Codex 桌面端 `response.completed` usage 事件
  - 解析 Codex 桌面端 `codex.rate_limits` 剩余额度事件
  - 文件监听 + 轮询兜底
  - 缓存最后一次有效快照，启动后先恢复可显示状态

## 数据源

第一版真实数据源是 Codex 桌面端本地 SQLite 日志：

```text
~/.codex/sqlite/logs_2.sqlite
~/.codex/logs_2.sqlite
```

CodexPlus 会读取最近的 Codex websocket 日志，解析其中的 usage 和 rate limits 事件，并聚合为统一模型：

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
  rateLimits
```

真实数据源细节见 [Codex 桌面端用量数据源](docs/codex-desktop-usage-source.md)。

## 隐私

- 默认只读取本机 Codex 桌面端日志。
- 默认不上传用量、路径、日志或 token 统计。
- 不需要 OpenAI API Key。
- 后续如果增加联网数据源，必须由用户显式启用，敏感凭据应进入 Keychain。

## 项目结构

```text
CodexPlus.xcodeproj
CodexPlus/
  CodexPlusApp.swift
  MenuBarContentView.swift
  Info.plist
  Assets.xcassets/
  Models/
    MenuBarDisplayMode.swift
    UsageSnapshot.swift
  Providers/
    CodexDesktopUsageProvider.swift
    CodexUsageLogParser.swift
    MockUsageProvider.swift
    UsageProvider.swift
  Services/
    UsageService.swift
  Settings/
    SettingsStore.swift
CodexPlusTests/
docs/
scripts/
```

核心关系：

```text
CodexPlusApp
  -> MenuBarContentView
  -> SettingsView
  -> SettingsStore
  -> UsageService
  -> UsageProvider
     -> CodexDesktopUsageProvider
     -> MockUsageProvider
```

## 本地开发

用 Xcode 运行：

1. 打开 `CodexPlus.xcodeproj`。
2. 选择 `CodexPlus` scheme。
3. 运行 App。
4. App 会显示在菜单栏，不显示 Dock 图标。

命令行测试：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project CodexPlus.xcodeproj \
  -scheme CodexPlus \
  -configuration Debug \
  -destination platform=macOS \
  -derivedDataPath /private/tmp/CodexPlusDerivedData \
  -parallel-testing-enabled NO
```

当前测试覆盖：

- 用量模型和预算状态
- Codex 日志解析
- 服务刷新、错误、缓存恢复和数据过期状态
- 菜单栏弹窗和设置窗口的 UI 冒烟渲染

## 打包发布

本地 Release 打包：

```sh
scripts/package-release.sh
```

默认生成：

```text
dist/CodexPlus-0.1.0+1.zip
```

Developer ID 签名：

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
scripts/package-release.sh
```

公证、staple 和最终分发说明见 [打包发布](docs/release.md)。当前已验证的最终分发包命名为：

```text
dist/CodexPlus-0.1.0+1.notarized.zip
```

## 后续方向

后续计划集中维护在 [TODO.md](TODO.md)。当前优先级较高的方向包括：

- 历史趋势图
- 更细的项目/会话维度聚合
- 自定义状态栏文字模板
- 自动更新机制
- 更完善的分发和安装体验

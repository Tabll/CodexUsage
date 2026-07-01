# Codex用量

Codex用量 是一个 macOS 菜单栏 App，用来近实时显示 Codex 桌面端的用量与剩余额度。仓库和 Xcode scheme 仍保留 `CodexPlus`，生成的 App 显示名是「Codex用量」。

当前版本：`0.2.1 (1)`
最低系统：macOS 26
产品定位：面向分发的本地优先 App

## 当前状态

Codex用量 已完成 MVP 到打包发布阶段：

- 默认从 Codex 桌面端本地日志读取用量数据。
- reset credits 仅在缓存超过 24 小时或用户手动刷新时，请求 ChatGPT 后端接口读取可用重置次数和过期时间。
- 状态栏默认显示 `5小时 x% 本周 x%`，用于快速查看 5 小时额度和每周额度。
- 菜单栏弹窗保持轻量，只展示核心用量概览、刷新、设置和退出。
- macOS 桌面小组件显示 5 小时额度、本周额度和核心 token 用量。
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
  - reset credits 可用次数，点击后展开每一次的授予时间和过期时间
  - 5 小时剩余额度和刷新时间
  - 每周剩余额度和刷新时间
  - 今日用量
  - 当前会话用量
  - 数据源状态
  - 最近更新时间
  - 手动刷新、打开设置、退出
- 桌面小组件：
  - 小尺寸：5 小时剩余、本周剩余、今日 token
  - 中尺寸：5 小时 / 本周剩余、刷新时间、今日 token、当前会话、更新时间
  - 通过 App Group 读取主 App 缓存的最后一次有效快照
- 设置窗口：
  - 状态栏显示内容
  - 数据源选择
  - 闲置主动轮询开关
  - 闲置和使用中刷新间隔
  - 每日预算
  - 警告阈值
  - macOS 通知开关
- 数据能力：
  - 解析 Codex 桌面端 `response.completed` usage 事件
  - 解析 Codex 桌面端 `codex.rate_limits` 剩余额度事件
  - 使用 `~/.codex/auth.json` 中的 Codex access token 查询 rate-limit reset credits，并只缓存汇总字段
  - 启动立即刷新，文件监听自动刷新，可配置闲置轮询兜底
  - 缓存最后一次有效快照，启动后先恢复可显示状态

## 数据源

主要用量数据源是 Codex 桌面端本地 SQLite 日志：

```text
~/.codex/logs_2.sqlite
~/.codex/sqlite/logs_2.sqlite
```

Codex用量 会检查候选数据库，选择最新可解析的 Codex websocket 日志，解析其中的 usage 和 rate limits 事件，并聚合为统一模型：

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

reset credits 数据来自：

```text
https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
```

Codex用量 会读取本机 `~/.codex/auth.json` 中的 `tokens.access_token` 作为 Bearer token。响应只保留 `available_count` 以及每条 credit 的 `status`、`title`、`granted_at`、`expires_at`。

## 隐私

- 用量统计仍只读取本机 Codex 桌面端日志。
- reset credits 请求只发送到 ChatGPT 官方后端接口，并按 24 小时缓存节流。
- 不打印、不展示、不缓存 access token、refresh token、cookie 或服务端完整唯一 ID。
- 不需要 OpenAI API Key。

## 项目结构

```text
CodexPlus.xcodeproj
CodexPlus/
  CodexPlusApp.swift
  MenuBarContentView.swift
  Info.plist
  CodexPlus.entitlements
  Assets.xcassets/
  Models/
    MenuBarDisplayMode.swift
    RateLimitResetCredits.swift
    UsageSnapshot.swift
  Providers/
    CodexDesktopUsageProvider.swift
    CodexUsageLogParser.swift
    MockUsageProvider.swift
    UsageProvider.swift
  Services/
    RateLimitResetCreditsService.swift
    UsageService.swift
  Settings/
    SettingsStore.swift
    SharedUsageCache.swift
CodexPlusWidget/
  CodexPlusWidgetBundle.swift
  Info.plist
  CodexPlusWidget.entitlements
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
  -> SharedUsageCache
     -> CodexPlusWidget
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
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

桌面小组件使用 App Group：

```text
group.com.weitianshu.CodexPlus
```

带签名运行或发布时，需要在 Apple Developer 里为主 App `com.weitianshu.CodexPlus` 和小组件 `com.weitianshu.CodexPlus.CodexPlusWidget` 配好 App Group 能力和对应 provisioning/profile。只做本地编译测试时，可以像上面的命令一样关闭签名。

### 签名和小组件验证

如果本地能编译但桌面小组件不显示，优先检查签名和 profile。WidgetKit 小组件需要主 App 和 `CodexPlusWidgetExtension` 都带有效签名、App Group entitlement，并且小组件扩展已经嵌入主 App。

Xcode GUI 配置：

1. 打开 `CodexPlus.xcodeproj`。
2. 在项目设置里分别选择 `CodexPlus` 和 `CodexPlusWidgetExtension` 两个 target。
3. 在 `Signing & Capabilities` 中选择开发团队并勾选 `Automatically manage signing`。
4. 确认两个 target 都有 App Group：`group.com.weitianshu.CodexPlus`。
5. 如果 Xcode 提示注册 Mac 或创建 Apple Development 证书，按提示完成。

命令行验证开发签名：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build \
  -project CodexPlus.xcodeproj \
  -scheme CodexPlus \
  -configuration Debug \
  -destination platform=macOS \
  -derivedDataPath build/AutoProvisionDebugDerivedData \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  ENABLE_HARDENED_RUNTIME=YES
```

检查构建产物：

```sh
APP_PATH="build/AutoProvisionDebugDerivedData/Build/Products/Debug/Codex用量.app"

test -d "$APP_PATH/Contents/PlugIns/CodexPlusWidgetExtension.appex"
codesign -d --entitlements - "$APP_PATH"
codesign -d --entitlements - "$APP_PATH/Contents/PlugIns/CodexPlusWidgetExtension.appex"
```

如果 `scripts/package-release.sh` 报 `requires a provisioning profile`，说明还缺 Developer ID 分发用 provisioning profile。需要在 Apple Developer 中为主 App 和 Widget Extension 分别创建或下载包含 App Group 能力的 Developer ID profile；Xcode 自动生成的 Mac Team 开发 profile 只适合本机开发验证，不等同于分发签名。

当前测试覆盖：

- 用量模型和预算状态
- Codex 日志解析
- 服务刷新、错误、缓存恢复和数据过期状态
- 菜单栏弹窗和设置窗口的 UI 冒烟渲染

## 打包发布

Release 打包需要使用包含 App Group 能力的签名配置：

```sh
CODE_SIGN_IDENTITY="<Developer ID Application identity>" \
DEVELOPMENT_TEAM="<TEAM_ID>" \
scripts/package-release.sh
```

生成：

```text
dist/CodexUsage-0.2.1+1.zip
```

只做本地编译和单元测试时使用 `CODE_SIGNING_ALLOWED=NO`；可运行的带小组件包需要为主 App 和小组件配置 `group.com.weitianshu.CodexPlus` App Group。

Developer ID 签名示例：

```sh
CODE_SIGN_IDENTITY="<Developer ID Application identity>" \
DEVELOPMENT_TEAM="<TEAM_ID>" \
scripts/package-release.sh
```

Developer ID、公证、staple 流程如下。`CODE_SIGN_IDENTITY` 使用钥匙串里的 Developer ID Application 证书，`<notary-profile>` 是通过 `xcrun notarytool store-credentials` 保存过的钥匙串 profile。

```sh
CODE_SIGN_IDENTITY="<Developer ID Application identity>" \
DEVELOPMENT_TEAM="<TEAM_ID>" \
scripts/package-release.sh

xcrun notarytool submit dist/CodexUsage-0.2.1+1.zip \
  --keychain-profile <notary-profile> \
  --wait

xcrun stapler staple build/ReleaseDerivedData/Build/Products/Release/Codex用量.app
xcrun stapler validate build/ReleaseDerivedData/Build/Products/Release/Codex用量.app

ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl \
  build/ReleaseDerivedData/Build/Products/Release/Codex用量.app \
  dist/CodexUsage-0.2.1+1.notarized.zip

spctl --assess --type execute --verbose=4 \
  build/ReleaseDerivedData/Build/Products/Release/Codex用量.app
```

公证、staple 和最终分发说明见 [打包发布](docs/release.md)。当前已验证的最终分发包命名为：

```text
dist/CodexUsage-0.2.1+1.notarized.zip
```

## 后续方向

后续计划集中维护在 [TODO.md](TODO.md)。当前优先级较高的方向包括：

- 历史趋势图
- 更细的项目/会话维度聚合
- 自定义状态栏文字模板
- 自动更新机制
- 更完善的分发和安装体验

# 打包发布

Codex用量 当前版本为 `0.2.0 (1)`，最低支持 macOS 26。

## 发布产物

本仓库提供一个可重复的本地打包脚本：

```sh
scripts/package-release.sh
```

配置签名后，默认产物：

```text
dist/CodexUsage-0.2.0+1.zip
```

脚本会执行 Release 构建，校验签名，确认 `AppIcon.icns` 已进入 App 包，并把 `Codex用量.app` 打成 zip。`dist/` 和 `build/` 是本地产物目录，不提交到 Git。

## 签名配置

当前版本包含 WidgetKit 小组件，并通过 App Group 与主 App 共享最后一次有效用量快照：

```text
group.com.weitianshu.CodexPlus
```

因此带签名运行或发布时，需要在 Apple Developer 中为以下 bundle id 配置 App Group 能力和对应 provisioning/profile：

```text
com.weitianshu.CodexPlus
com.weitianshu.CodexPlus.CodexPlusWidget
```

历史版本的默认 ad-hoc 签名配置为：

```text
CODE_SIGN_STYLE=Manual
CODE_SIGN_IDENTITY=-
ENABLE_HARDENED_RUNTIME=YES
```

加入 App Group entitlement 后，ad-hoc 签名不再适合作为可运行分发包。只做本地编译和单元测试时，可以传入 `CODE_SIGNING_ALLOWED=NO`；真正安装验证和发布应使用包含 App Group 能力的签名配置。

如需面向公开分发，使用 Developer ID 证书重新打包：

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
scripts/package-release.sh
```

使用 Developer ID 证书时，脚本会自动传入 `OTHER_CODE_SIGN_FLAGS=--timestamp`，确保签名包含 Apple 公证所需的安全时间戳。

公开分发前还需要完成 Apple notarization。当前脚本不自动上传公证，因为需要开发者账号、App 专用密码或 API Key，以及团队的发布策略。以已经保存到钥匙串的 `codexplus-notary` profile 为例：

```sh
xcrun notarytool submit dist/CodexUsage-0.2.0+1.zip \
  --keychain-profile codexplus-notary \
  --wait

xcrun stapler staple build/ReleaseDerivedData/Build/Products/Release/Codex用量.app
xcrun stapler validate build/ReleaseDerivedData/Build/Products/Release/Codex用量.app

ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl \
  build/ReleaseDerivedData/Build/Products/Release/Codex用量.app \
  dist/CodexUsage-0.2.0+1.notarized.zip
```

最终面向用户分发 `dist/CodexUsage-0.2.0+1.notarized.zip`。

## 安装说明

1. 解压 `dist/CodexUsage-0.2.0+1.zip`。
2. 将 `Codex用量.app` 拖入 `/Applications`。
3. 启动 `Codex用量.app`。
4. App 启动后只显示在菜单栏，不显示 Dock 图标。
5. 首次开启预算通知时，按系统提示允许通知权限。

Codex用量 默认读取 Codex 桌面端本地用量日志，不需要配置 API Key。

## 故障排查

如果 App 打不开：

- 确认系统版本是 macOS 26 或更高。
- 如果系统提示无法验证开发者，说明当前包未公证。内部测试可以在“系统设置 -> 隐私与安全性”中允许打开；公开分发应改用 Developer ID 签名并完成 notarization。
- 如果 zip 解压后 App 被隔离，可以执行：

```sh
xattr -dr com.apple.quarantine /Applications/Codex用量.app
```

如果菜单栏没有出现：

- 确认 App 正在运行。Codex用量 是菜单栏 App，不会显示 Dock 图标。
- 打开“活动监视器”，搜索 `Codex用量`。
- 重新启动 App，或从活动监视器退出后再打开。

如果没有真实用量：

- 确认 Codex 桌面端已经运行并产生过用量日志。
- 确认本机存在 `~/.codex/sqlite/logs_2.sqlite` 或 `~/.codex/logs_2.sqlite`。
- 菜单栏弹窗会显示当前数据源和错误状态；如果日志暂时没有可解析 usage，等待 Codex 完成一次响应后刷新。

如果通知不出现：

- 在系统设置里确认 Codex用量 的通知权限已开启。
- 在 Codex用量 弹窗里确认“每日预算”和“macOS 通知”都已开启。
- 通知只会在当天首次达到警告阈值或首次超过预算时发送，避免重复打扰。

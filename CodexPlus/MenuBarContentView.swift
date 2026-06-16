import SwiftUI

struct MenuBarContentView: View {
    let snapshot: UsageSnapshot?
    let status: UsageServiceStatus
    let budgetState: UsageBudgetState
    let providerName: String
    let lastErrorMessage: String?
    @Binding var menuBarDisplayMode: MenuBarDisplayMode
    @Binding var dataSourceMode: UsageDataSourceMode
    @Binding var isDailyBudgetEnabled: Bool
    @Binding var dailyBudgetTokens: Int
    @Binding var warningThresholdPercent: Int
    @Binding var budgetNotificationsEnabled: Bool
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            HStack(spacing: 10) {
                MetricTile(
                    title: "当前会话",
                    value: currentSessionText,
                    caption: menuBarDisplayMode == .currentSessionTokens ? "状态栏显示" : "tokens",
                    systemImage: "bolt.horizontal"
                )

                MetricTile(
                    title: "今日用量",
                    value: todayText,
                    caption: menuBarDisplayMode == .todayTokens ? "状态栏显示" : "tokens",
                    systemImage: "chart.bar.xaxis"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "剩余额度")

                HStack(spacing: 10) {
                    MetricTile(
                        title: "5 小时",
                        value: shortWindowRemainingText,
                        caption: shortWindowResetText,
                        systemImage: "hourglass"
                    )

                    MetricTile(
                        title: "每周",
                        value: weeklyWindowRemainingText,
                        caption: weeklyWindowResetText,
                        systemImage: "calendar"
                    )
                }

                InfoRow(
                    title: "计划",
                    value: planTypeText,
                    systemImage: "person.crop.circle.badge.checkmark"
                )

                InfoRow(
                    title: "额度状态",
                    value: rateLimitStatusText,
                    systemImage: "checkmark.seal"
                )

                InfoRow(
                    title: "额度更新时间",
                    value: rateLimitUpdatedText,
                    systemImage: "clock.arrow.circlepath"
                )

                if let monthlyWindow = snapshot?.rateLimits?.monthlyWindow {
                    InfoRow(
                        title: "月度窗口",
                        value: monthlyWindowText(monthlyWindow),
                        systemImage: "calendar.badge.clock"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "预算与提醒")

                HStack(spacing: 10) {
                    MetricTile(
                        title: "预算",
                        value: budgetPercentText,
                        caption: budgetUsageCaption,
                        systemImage: "gauge"
                    )

                    MetricTile(
                        title: "剩余",
                        value: budgetRemainingText,
                        caption: budgetWarningCaption,
                        systemImage: "bell.badge"
                    )
                }

                InfoRow(
                    title: "预算状态",
                    value: budgetState.title,
                    systemImage: "checkmark.shield"
                )

                Toggle(isOn: $isDailyBudgetEnabled) {
                    Label("每日预算", systemImage: "gauge")
                }
                .toggleStyle(.switch)

                Stepper(
                    value: $dailyBudgetTokens,
                    in: UsageBudgetConfiguration.minimumDailyLimitTokens...UsageBudgetConfiguration.maximumDailyLimitTokens,
                    step: 10_000
                ) {
                    SettingValueRow(
                        title: "预算额度",
                        value: UsageFormatting.tokens(dailyBudgetTokens),
                        systemImage: "number"
                    )
                }
                .disabled(!isDailyBudgetEnabled)

                Stepper(
                    value: $warningThresholdPercent,
                    in: UsageBudgetConfiguration.minimumWarningThresholdPercent...UsageBudgetConfiguration.maximumWarningThresholdPercent,
                    step: 5
                ) {
                    SettingValueRow(
                        title: "警告阈值",
                        value: "\(warningThresholdPercent)%",
                        systemImage: "bell"
                    )
                }
                .disabled(!isDailyBudgetEnabled)

                Toggle(isOn: $budgetNotificationsEnabled) {
                    Label("macOS 通知", systemImage: "bell.badge")
                }
                .toggleStyle(.switch)
                .disabled(!isDailyBudgetEnabled)
            }

            VStack(spacing: 8) {
                InfoRow(
                    title: "状态",
                    value: status.title,
                    systemImage: status.menuBarSystemImage
                )

                InfoRow(
                    title: "状态栏显示",
                    value: menuBarDisplayMode.title,
                    systemImage: menuBarDisplayMode.systemImage
                )

                InfoRow(
                    title: "预估花费",
                    value: estimatedCostText,
                    systemImage: "creditcard"
                )

                InfoRow(
                    title: "数据源",
                    value: providerName,
                    systemImage: "desktopcomputer"
                )

                InfoRow(
                    title: "更新时间",
                    value: lastUpdatedText,
                    systemImage: "clock"
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "当前会话详情")

                InfoRow(
                    title: "输入",
                    value: inputTokensText,
                    systemImage: "square.and.pencil"
                )

                InfoRow(
                    title: "输出",
                    value: outputTokensText,
                    systemImage: "text.bubble"
                )

                InfoRow(
                    title: "缓存输入",
                    value: cachedInputTokensText,
                    systemImage: "tray.full"
                )

                InfoRow(
                    title: "推理",
                    value: reasoningTokensText,
                    systemImage: "brain.head.profile"
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "设置")

                Picker("状态栏显示", selection: $menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("数据源", selection: $dataSourceMode) {
                    ForEach(UsageDataSourceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            if let lastErrorMessage, !lastErrorMessage.isEmpty {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button(action: onRefresh) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Spacer()

                Button(role: .destructive, action: onQuit) {
                    Label("退出", systemImage: "power")
                }
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("CodexPlus")
                    .font(.headline)

                Text("Codex 桌面端用量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(status.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(statusColor.opacity(0.12))
                )
        }
    }

    private var currentSessionText: String {
        guard let snapshot else {
            return "--"
        }

        return UsageFormatting.tokens(snapshot.totalTokens)
    }

    private var todayText: String {
        guard let snapshot else {
            return "--"
        }

        return UsageFormatting.tokens(snapshot.todayTotalTokens)
    }

    private var shortWindowRemainingText: String {
        UsageFormatting.remainingPercent(snapshot?.rateLimits?.shortWindow)
    }

    private var weeklyWindowRemainingText: String {
        UsageFormatting.remainingPercent(snapshot?.rateLimits?.weeklyWindow)
    }

    private var shortWindowResetText: String {
        resetCaption(for: snapshot?.rateLimits?.shortWindow)
    }

    private var weeklyWindowResetText: String {
        resetCaption(for: snapshot?.rateLimits?.weeklyWindow)
    }

    private var planTypeText: String {
        snapshot?.rateLimits?.planType ?? "--"
    }

    private var rateLimitStatusText: String {
        guard let rateLimits = snapshot?.rateLimits else {
            return "等待数据"
        }

        if rateLimits.limitReached {
            return "已达上限"
        }

        return rateLimits.allowed ? "可用" : "受限"
    }

    private var rateLimitUpdatedText: String {
        UsageFormatting.time(snapshot?.rateLimits?.updatedAt)
    }

    private var budgetPercentText: String {
        UsageFormatting.percent(budgetState.usedPercent)
    }

    private var budgetUsageCaption: String {
        guard let dailyLimitTokens = budgetState.dailyLimitTokens else {
            return "未开启"
        }

        return "\(UsageFormatting.tokens(budgetState.usedTokens)) / \(UsageFormatting.tokens(dailyLimitTokens))"
    }

    private var budgetRemainingText: String {
        guard let remainingTokens = budgetState.remainingTokens else {
            return "--"
        }

        return UsageFormatting.tokens(remainingTokens)
    }

    private var budgetWarningCaption: String {
        guard let warningLimitTokens = budgetState.warningLimitTokens else {
            return "等待设置"
        }

        return "阈值 \(budgetState.configuration.warningThresholdPercent)% · \(UsageFormatting.tokens(warningLimitTokens))"
    }

    private var estimatedCostText: String {
        UsageFormatting.cost(snapshot?.estimatedCost)
    }

    private var lastUpdatedText: String {
        UsageFormatting.time(snapshot?.updatedAt)
    }

    private var inputTokensText: String {
        guard let snapshot else {
            return "--"
        }

        return UsageFormatting.tokens(snapshot.inputTokens)
    }

    private var outputTokensText: String {
        guard let snapshot else {
            return "--"
        }

        return UsageFormatting.tokens(snapshot.outputTokens)
    }

    private var cachedInputTokensText: String {
        guard let snapshot else {
            return "--"
        }

        return UsageFormatting.tokens(snapshot.cachedInputTokens)
    }

    private var reasoningTokensText: String {
        guard let snapshot else {
            return "--"
        }

        return UsageFormatting.tokens(snapshot.reasoningTokens)
    }

    private func resetCaption(for window: UsageRateLimitWindow?) -> String {
        guard let window else {
            return "等待数据"
        }

        return "刷新 \(UsageFormatting.time(window.resetAt))"
    }

    private func monthlyWindowText(_ window: UsageRateLimitWindow) -> String {
        "\(window.remainingPercent)% · 刷新 \(UsageFormatting.time(window.resetAt))"
    }

    private var statusColor: Color {
        switch status {
        case .idle:
            return .secondary
        case .refreshing:
            return .blue
        case .current:
            return .green
        case .stale:
            return .orange
        case .warning:
            return .orange
        case .failed:
            return .red
        }
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let caption: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.callout)
    }
}

private struct SettingValueRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

#Preview {
    MenuBarContentView(
        snapshot: .preview,
        status: .current,
        budgetState: UsageBudgetState(
            configuration: UsageBudgetConfiguration(isEnabled: true),
            usedTokens: UsageSnapshot.preview.todayTotalTokens
        ),
        providerName: "Codex 桌面端（Mock）",
        lastErrorMessage: nil,
        menuBarDisplayMode: .constant(.currentSessionTokens),
        dataSourceMode: .constant(.codexDesktop),
        isDailyBudgetEnabled: .constant(true),
        dailyBudgetTokens: .constant(150_000),
        warningThresholdPercent: .constant(80),
        budgetNotificationsEnabled: .constant(false),
        onRefresh: {},
        onQuit: {}
    )
    .frame(width: 320)
}

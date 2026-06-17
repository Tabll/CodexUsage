import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    let snapshot: UsageSnapshot?
    let status: UsageServiceStatus
    let budgetState: UsageBudgetState
    let providerName: String
    let lastErrorMessage: String?
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 10) {
                RateLimitTile(
                    title: "5小时",
                    value: shortWindowRemainingText,
                    caption: shortWindowResetText,
                    systemImage: "hourglass"
                )

                RateLimitTile(
                    title: "本周",
                    value: weeklyWindowRemainingText,
                    caption: weeklyWindowResetText,
                    systemImage: "calendar"
                )
            }

            VStack(spacing: 7) {
                CompactInfoRow(title: "状态", value: status.title, systemImage: status.menuBarSystemImage)
                CompactInfoRow(title: "今日", value: todayText, systemImage: "chart.bar.xaxis")
                CompactInfoRow(title: "当前会话", value: currentSessionText, systemImage: "bolt.horizontal")
                CompactInfoRow(title: "数据源", value: providerName, systemImage: "desktopcomputer")
                CompactInfoRow(title: "更新时间", value: lastUpdatedText, systemImage: "clock")

                if let monthlyWindow = snapshot?.rateLimits?.monthlyWindow {
                    CompactInfoRow(
                        title: "月度",
                        value: monthlyWindowText(monthlyWindow),
                        systemImage: "calendar.badge.clock"
                    )
                }
            }

            if let lastErrorMessage, !lastErrorMessage.isEmpty {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 10) {
                Button(action: onRefresh) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Button {
                    openWindow(id: "settings")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("设置", systemImage: "gearshape")
                }

                Spacer()

                Button(role: .destructive, action: onQuit) {
                    Label("退出", systemImage: "power")
                }
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(UsageFormatting.rateLimitSummary(snapshot?.rateLimits))
                    .font(.headline)
                    .monospacedDigit()

                Text(rateLimitSubhead)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .accessibilityLabel(status.title)
        }
    }

    private var rateLimitSubhead: String {
        guard let rateLimits = snapshot?.rateLimits else {
            return "等待 Codex 桌面端用量数据"
        }

        if rateLimits.limitReached {
            return "额度已达上限"
        }

        return rateLimits.allowed ? "额度可用" : "额度受限"
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

    private var lastUpdatedText: String {
        UsageFormatting.time(snapshot?.updatedAt)
    }

    private func resetCaption(for window: UsageRateLimitWindow?) -> String {
        guard let window else {
            return "等待数据"
        }

        return "刷新 \(UsageFormatting.time(window.resetAt))"
    }

    private func monthlyWindowText(_ window: UsageRateLimitWindow) -> String {
        "\(window.remainingPercent)% · \(UsageFormatting.time(window.resetAt))"
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

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore

    let onBudgetConfigurationChange: (UsageBudgetConfiguration) -> Void
    let onDataSourceModeChange: (UsageDataSourceMode) -> Void
    let onRefreshConfigurationChange: (UsageRefreshConfiguration) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("CodexPlus 设置")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "状态栏")

                    SettingsPickerRow(title: "显示内容", systemImage: "menubar.rectangle") {
                        Picker("", selection: $settingsStore.menuBarDisplayMode) {
                            ForEach(MenuBarDisplayMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "数据源")

                    SettingsPickerRow(title: "用量来源", systemImage: "desktopcomputer") {
                        Picker("", selection: $settingsStore.dataSourceMode) {
                            ForEach(UsageDataSourceMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "刷新")

                    Toggle(isOn: $settingsStore.isIdlePollingEnabled) {
                        Label("闲置主动轮询", systemImage: "clock.arrow.circlepath")
                    }
                    .toggleStyle(.switch)

                    Stepper(
                        value: $settingsStore.idleRefreshIntervalMinutes,
                        in: UsageServiceRefreshDefaults.minimumIdleRefreshIntervalMinutes...UsageServiceRefreshDefaults.maximumIdleRefreshIntervalMinutes,
                        step: 5
                    ) {
                        SettingsValueRow(
                            title: "闲置间隔",
                            value: "\(settingsStore.idleRefreshIntervalMinutes) 分钟",
                            systemImage: "timer"
                        )
                    }
                    .disabled(!settingsStore.isIdlePollingEnabled)

                    Stepper(
                        value: $settingsStore.activeRefreshIntervalSeconds,
                        in: UsageServiceRefreshDefaults.minimumActiveRefreshIntervalSeconds...UsageServiceRefreshDefaults.maximumActiveRefreshIntervalSeconds,
                        step: 5
                    ) {
                        SettingsValueRow(
                            title: "使用中间隔",
                            value: "\(settingsStore.activeRefreshIntervalSeconds) 秒",
                            systemImage: "bolt.badge.clock"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "预算与提醒")

                    Toggle(isOn: $settingsStore.isDailyBudgetEnabled) {
                        Label("每日预算", systemImage: "gauge")
                    }
                    .toggleStyle(.switch)

                    Stepper(
                        value: $settingsStore.dailyBudgetTokens,
                        in: UsageBudgetConfiguration.minimumDailyLimitTokens...UsageBudgetConfiguration.maximumDailyLimitTokens,
                        step: 10_000
                    ) {
                        SettingsValueRow(
                            title: "预算额度",
                            value: UsageFormatting.tokens(settingsStore.dailyBudgetTokens),
                            systemImage: "number"
                        )
                    }
                    .disabled(!settingsStore.isDailyBudgetEnabled)

                    Stepper(
                        value: $settingsStore.warningThresholdPercent,
                        in: UsageBudgetConfiguration.minimumWarningThresholdPercent...UsageBudgetConfiguration.maximumWarningThresholdPercent,
                        step: 5
                    ) {
                        SettingsValueRow(
                            title: "警告阈值",
                            value: "\(settingsStore.warningThresholdPercent)%",
                            systemImage: "bell"
                        )
                    }
                    .disabled(!settingsStore.isDailyBudgetEnabled)

                    Toggle(isOn: $settingsStore.budgetNotificationsEnabled) {
                        Label("macOS 通知", systemImage: "bell.badge")
                    }
                    .toggleStyle(.switch)
                    .disabled(!settingsStore.isDailyBudgetEnabled)
                }
            }
            .padding(22)
        }
        .frame(width: 470)
        .onChange(of: settingsStore.budgetConfiguration) { _, configuration in
            onBudgetConfigurationChange(configuration)
        }
        .onChange(of: settingsStore.dataSourceMode) { _, dataSourceMode in
            onDataSourceModeChange(dataSourceMode)
        }
        .onChange(of: settingsStore.refreshConfiguration) { _, configuration in
            onRefreshConfigurationChange(configuration)
        }
    }
}

private struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
}

private struct SettingsPickerRow<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let picker: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            picker()
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 190, alignment: .trailing)
        }
        .font(.callout)
    }
}

private struct RateLimitTile: View {
    let title: String
    let value: String
    let caption: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct CompactInfoRow: View {
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
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}

private struct SettingsValueRow: View {
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

#Preview("Menu") {
    MenuBarContentView(
        snapshot: .preview,
        status: .current,
        budgetState: UsageBudgetState(
            configuration: UsageBudgetConfiguration(isEnabled: true),
            usedTokens: UsageSnapshot.preview.todayTotalTokens
        ),
        providerName: "Codex 桌面端（Mock）",
        lastErrorMessage: nil,
        onRefresh: {},
        onQuit: {}
    )
    .frame(width: 300)
}

#Preview("Settings") {
    SettingsView(
        settingsStore: SettingsStore(defaults: UserDefaults(suiteName: "CodexPlus.preview") ?? .standard),
        onBudgetConfigurationChange: { _ in },
        onDataSourceModeChange: { _ in },
        onRefreshConfigurationChange: { _ in }
    )
}

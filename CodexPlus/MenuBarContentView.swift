import AppKit
import Charts
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

    @State private var isUsageChartPresented = false
    @State private var isLatestMessagePresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsSection("状态栏") {
                LazyVGrid(columns: displayModeColumns, alignment: .leading, spacing: 8) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        SettingsOptionButton(
                            title: mode.title,
                            systemImage: mode.systemImage,
                            isSelected: settingsStore.menuBarDisplayMode == mode
                        ) {
                            settingsStore.menuBarDisplayMode = mode
                        }
                    }
                }
            }

            settingsSection("数据源") {
                HStack(spacing: 8) {
                    ForEach(UsageDataSourceMode.allCases) { mode in
                        SettingsOptionButton(
                            title: mode.title,
                            systemImage: mode.systemImage,
                            isSelected: settingsStore.dataSourceMode == mode
                        ) {
                            settingsStore.dataSourceMode = mode
                        }
                    }
                }
            }

            settingsSection("用量统计") {
                VStack(spacing: 8) {
                    SettingsActionButton(
                        title: "用量图表",
                        detail: "最近一周 / 30 天",
                        systemImage: "chart.xyaxis.line"
                    ) {
                        isUsageChartPresented = true
                    }

                    SettingsActionButton(
                        title: "最近消息",
                        detail: "查看完整日志",
                        systemImage: "text.bubble"
                    ) {
                        isLatestMessagePresented = true
                    }
                }
            }

            settingsSection("刷新") {
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

            settingsSection("预算与提醒") {
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
        .frame(width: 560)
        .tint(.blue)
        .sheet(isPresented: $isUsageChartPresented) {
            UsageHistoryChartSheet(dataSourceMode: settingsStore.dataSourceMode)
                .frame(width: 760, height: 540)
        }
        .sheet(isPresented: $isLatestMessagePresented) {
            LatestMessageSheet(dataSourceMode: settingsStore.dataSourceMode)
                .frame(width: 760, height: 620)
        }
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

    private var displayModeColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: title)
            content()
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

private struct SettingsOptionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)

                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.blue)
                }
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? Color.blue : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 1.2 : 0.6
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsActionButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.14))

                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.blue)
                }
                .frame(width: 32, height: 32)

                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)

                Spacer()

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.12),
                                Color.blue.opacity(0.035)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.22), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LatestMessageSheet: View {
    @Environment(\.dismiss) private var dismiss

    let dataSourceMode: UsageDataSourceMode

    @State private var message: CodexLogMessage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var didCopyContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            content
        }
        .padding(22)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadLatestMessage()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("最近消息")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("最新一条日志 · \(dataSourceMode.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await loadLatestMessage()
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)

            Button {
                copyContent()
            } label: {
                Label(didCopyContent ? "已复制" : "复制内容", systemImage: didCopyContent ? "checkmark" : "doc.on.doc")
            }
            .disabled(message == nil)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("关闭")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LatestMessagePanel {
                ProgressView("正在读取最近消息")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let errorMessage {
            LatestMessagePanel {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    Text("无法读取最近消息")
                        .font(.headline)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
        } else if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LatestMessageMetadataGrid(message: message)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: "text.alignleft")
                                .foregroundStyle(Color.blue)

                            Text("内容")
                                .font(.headline)

                            Spacer()

                            Text("\(message.contentText.count) 字符")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        ScrollView {
                            Text(message.contentText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(minHeight: 230)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.12), lineWidth: 0.8)
                        )
                    }
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 0.8)
            )
        }
    }

    @MainActor
    private func loadLatestMessage() async {
        isLoading = true
        errorMessage = nil
        didCopyContent = false

        do {
            let provider = makeLatestMessageProvider()
            let latestMessage = try await provider.fetchLatestLogMessage()

            guard !Task.isCancelled else {
                return
            }

            message = latestMessage
            isLoading = false
        } catch {
            guard !Task.isCancelled else {
                return
            }

            message = nil
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func makeLatestMessageProvider() -> any UsageLatestMessageProvider {
        switch dataSourceMode {
        case .codexDesktop:
            return CodexDesktopUsageProvider()
        case .mock:
            return MockUsageProvider()
        }
    }

    private func copyContent() {
        guard let message else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.contentText, forType: .string)
        didCopyContent = true
    }
}

private struct LatestMessagePanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.16), lineWidth: 0.8)
                )

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LatestMessageMetadataGrid: View {
    let message: CodexLogMessage

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(Color.blue)

                Text("数据")
                    .font(.headline)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Array(message.metadataRows.enumerated()), id: \.offset) { _, row in
                    LatestMessageMetadataRow(title: row.title, value: row.value)
                }
            }
        }
    }
}

private struct LatestMessageMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .monospacedDigit()
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.blue.opacity(0.10), lineWidth: 0.7)
        )
    }
}

private struct UsageHistoryChartSheet: View {
    @Environment(\.dismiss) private var dismiss

    let dataSourceMode: UsageDataSourceMode

    @State private var selectedPeriod: UsageHistoryPeriod = .last7Days
    @State private var summaries: [DailyUsageSummary] = []
    @State private var selectedSummary: DailyUsageSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            metrics

            chartPanel

            footer
        }
        .padding(22)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: selectedPeriod) {
            await loadHistory()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("用量图表")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("按天汇总 · \(dataSourceMode.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("范围", selection: $selectedPeriod) {
                ForEach(UsageHistoryPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)

            Button {
                Task {
                    await loadHistory()
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("关闭")
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            UsageHistoryMetricTile(
                title: "总 Tokens",
                value: UsageFormatting.tokens(periodTotalTokens),
                systemImage: "sum"
            )

            UsageHistoryMetricTile(
                title: "日均 Tokens",
                value: UsageFormatting.tokens(averageDailyTokens),
                systemImage: "chart.bar"
            )

            UsageHistoryMetricTile(
                title: "峰值日期",
                value: peakDayText,
                systemImage: "arrow.up.right"
            )
        }
    }

    private var chartPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.16), lineWidth: 0.8)
                )

            if isLoading {
                ProgressView("正在读取用量")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    Text("无法读取用量图表")
                        .font(.headline)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                usageChart
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .padding(.bottom, 14)
                    .padding(.leading, 8)
            }
        }
        .frame(height: 300)
    }

    private var usageChart: some View {
        Chart {
            ForEach(summaries) { summary in
                AreaMark(
                    x: .value("日期", summary.date, unit: .day),
                    y: .value("总 Tokens", summary.totalTokens)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.28),
                            Color.blue.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", summary.date, unit: .day),
                    y: .value("总 Tokens", summary.totalTokens)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.33, blue: 0.95),
                            Color.blue
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                PointMark(
                    x: .value("日期", summary.date, unit: .day),
                    y: .value("总 Tokens", summary.totalTokens)
                )
                .symbolSize(selectedSummary?.date == summary.date ? 80 : 36)
                .foregroundStyle(Color.blue)
            }

            if let selectedSummary {
                RuleMark(x: .value("选中日期", selectedSummary.date, unit: .day))
                    .foregroundStyle(Color.blue.opacity(0.34))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 8) {
                        UsageHistoryDetailCard(summary: selectedSummary)
                    }
            }
        }
        .chartYScale(domain: 0...chartMaxY)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: selectedPeriod == .last7Days ? 1 : 5)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.blue.opacity(0.08))
                AxisTick()
                    .foregroundStyle(Color.blue.opacity(0.18))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(UsageHistoryFormatting.shortDay(date))
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(Color.blue.opacity(0.10))
                AxisTick()
                    .foregroundStyle(Color.blue.opacity(0.18))
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(UsageFormatting.tokens(tokens))
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        updateSelection(from: phase, proxy: proxy, geometry: geometry)
                    }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("悬停数据点查看详情", systemImage: "cursorarrow.motionlines")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("更新时间 \(UsageFormatting.time(loadedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var periodTotalTokens: Int {
        summaries.reduce(0) { $0 + $1.totalTokens }
    }

    private var averageDailyTokens: Int {
        guard !summaries.isEmpty else {
            return 0
        }

        return periodTotalTokens / summaries.count
    }

    private var peakDayText: String {
        guard let peak = summaries.max(by: { $0.totalTokens < $1.totalTokens }),
              peak.totalTokens > 0 else {
            return "--"
        }

        return UsageHistoryFormatting.shortDay(peak.date)
    }

    private var chartMaxY: Int {
        let maxTokens = summaries.map(\.totalTokens).max() ?? 0
        let padding = max(maxTokens / 5, 1)
        return max(maxTokens + padding, 1)
    }

    @MainActor
    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        selectedSummary = nil
        loadedAt = nil

        do {
            let provider = makeHistoryProvider()
            let history = try await provider.fetchDailyUsageHistory(days: selectedPeriod.dayCount)

            guard !Task.isCancelled else {
                return
            }

            summaries = history
            selectedSummary = nil
            loadedAt = Date()
            isLoading = false
        } catch {
            guard !Task.isCancelled else {
                return
            }

            summaries = []
            errorMessage = error.localizedDescription
            loadedAt = nil
            isLoading = false
        }
    }

    private func makeHistoryProvider() -> any UsageHistoryProvider {
        switch dataSourceMode {
        case .codexDesktop:
            return CodexDesktopUsageProvider()
        case .mock:
            return MockUsageProvider()
        }
    }

    private func updateSelection(
        from phase: HoverPhase,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        switch phase {
        case .active(let location):
            guard let plotFrameAnchor = proxy.plotFrame else {
                selectedSummary = nil
                return
            }

            let plotFrame = geometry[plotFrameAnchor]
            guard plotFrame.contains(location) else {
                selectedSummary = nil
                return
            }

            let relativeX = location.x - plotFrame.origin.x
            guard let date = proxy.value(atX: relativeX, as: Date.self) else {
                selectedSummary = nil
                return
            }

            selectedSummary = nearestSummary(to: date)
        case .ended:
            selectedSummary = nil
        }
    }

    private func nearestSummary(to date: Date) -> DailyUsageSummary? {
        summaries.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}

private struct UsageHistoryMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.blue)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.13), lineWidth: 0.8)
        )
    }
}

private struct UsageHistoryDetailCard: View {
    let summary: DailyUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.blue)

                Text(UsageHistoryFormatting.fullDay(summary.date))
                    .fontWeight(.semibold)
            }

            Divider()

            UsageHistoryDetailRow(title: "输入 Tokens", value: summary.inputTokens)
            UsageHistoryDetailRow(title: "输出 Tokens", value: summary.outputTokens)
            UsageHistoryDetailRow(title: "缓存输入 Tokens", value: summary.cachedInputTokens)
            UsageHistoryDetailRow(title: "推理 Tokens", value: summary.reasoningTokens)
            UsageHistoryDetailRow(title: "总 Tokens", value: summary.totalTokens, isEmphasized: true)
        }
        .font(.caption)
        .padding(10)
        .frame(width: 184, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.blue.opacity(0.14), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.22), lineWidth: 0.8)
        )
    }
}

private struct UsageHistoryDetailRow: View {
    let title: String
    let value: Int
    var isEmphasized = false

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(isEmphasized ? Color.primary : Color.secondary)

            Spacer()

            Text(UsageFormatting.tokens(value))
                .fontWeight(isEmphasized ? .semibold : .medium)
                .monospacedDigit()
        }
    }
}

private enum UsageHistoryFormatting {
    static func shortDay(_ date: Date) -> String {
        shortDayFormatter.string(from: date)
    }

    static func fullDay(_ date: Date) -> String {
        fullDayFormatter.string(from: date)
    }

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
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

#if DEBUG
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
#endif

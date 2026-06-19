import SwiftUI
import WidgetKit

@main
struct CodexPlusWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexUsageWidget()
    }
}

struct CodexUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedUsageCacheDefaults.widgetKind,
            provider: CodexUsageTimelineProvider()
        ) { entry in
            CodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex用量")
        .description("显示 Codex 桌面端额度和 token 用量。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CodexUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct CodexUsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexUsageEntry {
        CodexUsageEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexUsageEntry) -> Void) {
        let snapshot = context.isPreview ? UsageSnapshot.preview : loadCachedSnapshot()
        completion(CodexUsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexUsageEntry>) -> Void) {
        let entry = CodexUsageEntry(date: Date(), snapshot: loadCachedSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadCachedSnapshot() -> UsageSnapshot? {
        SharedUsageCache().cachedSnapshot()
    }
}

struct CodexUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: CodexUsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemMedium:
                    mediumContent(snapshot)
                default:
                    smallContent(snapshot)
                }
            } else {
                emptyContent
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func smallContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader(snapshot)

            VStack(spacing: 8) {
                RateLimitWidgetRow(
                    title: "5小时",
                    value: UsageFormatting.remainingPercent(snapshot.rateLimits?.shortWindow),
                    percent: snapshot.rateLimits?.shortWindow?.remainingPercent,
                    systemImage: "hourglass"
                )

                RateLimitWidgetRow(
                    title: "本周",
                    value: UsageFormatting.remainingPercent(snapshot.rateLimits?.weeklyWindow),
                    percent: snapshot.rateLimits?.weeklyWindow?.remainingPercent,
                    systemImage: "calendar"
                )
            }

            Spacer(minLength: 0)

            Text("今日 \(UsageFormatting.tokens(snapshot.todayTotalTokens))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(14)
    }

    private func mediumContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader(snapshot)

            HStack(spacing: 10) {
                RateLimitWidgetTile(
                    title: "5小时",
                    value: UsageFormatting.remainingPercent(snapshot.rateLimits?.shortWindow),
                    resetText: resetText(for: snapshot.rateLimits?.shortWindow),
                    percent: snapshot.rateLimits?.shortWindow?.remainingPercent,
                    systemImage: "hourglass"
                )

                RateLimitWidgetTile(
                    title: "本周",
                    value: UsageFormatting.remainingPercent(snapshot.rateLimits?.weeklyWindow),
                    resetText: resetText(for: snapshot.rateLimits?.weeklyWindow),
                    percent: snapshot.rateLimits?.weeklyWindow?.remainingPercent,
                    systemImage: "calendar"
                )
            }

            HStack(spacing: 10) {
                MetricWidgetItem(
                    title: "今日",
                    value: UsageFormatting.tokens(snapshot.todayTotalTokens),
                    systemImage: "chart.bar.xaxis"
                )

                MetricWidgetItem(
                    title: "会话",
                    value: UsageFormatting.tokens(snapshot.totalTokens),
                    systemImage: "bolt.horizontal"
                )

                MetricWidgetItem(
                    title: "更新",
                    value: UsageFormatting.time(snapshot.updatedAt),
                    systemImage: "clock"
                )
            }
        }
        .padding(14)
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "hourglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("等待用量")
                .font(.headline)

            Text("Codex用量刷新后显示")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    private func widgetHeader(_ snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)

            Text("Codex用量")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            statusDot(for: snapshot)
        }
    }

    private func statusDot(for snapshot: UsageSnapshot) -> some View {
        Circle()
            .fill(statusColor(for: snapshot))
            .frame(width: 7, height: 7)
            .accessibilityLabel(snapshot.rateLimits?.limitReached == true ? "额度已达上限" : "额度可用")
    }

    private func statusColor(for snapshot: UsageSnapshot) -> Color {
        if snapshot.rateLimits?.limitReached == true {
            return .red
        }

        if snapshot.rateLimits?.allowed == false {
            return .orange
        }

        return .green
    }

    private func resetText(for window: UsageRateLimitWindow?) -> String {
        guard let window else {
            return "等待数据"
        }

        return "刷新 \(UsageFormatting.monthDayTime(window.resetAt))"
    }
}

private struct RateLimitWidgetRow: View {
    let title: String
    let value: String
    let percent: Int?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            ProgressView(value: progressValue)
                .tint(progressColor)
        }
    }

    private var progressValue: Double {
        guard let percent else {
            return 0
        }

        return Double(percent) / 100
    }

    private var progressColor: Color {
        guard let percent else {
            return .secondary
        }

        if percent <= 10 {
            return .red
        }

        if percent <= 25 {
            return .orange
        }

        return .green
    }
}

private struct RateLimitWidgetTile: View {
    let title: String
    let value: String
    let resetText: String
    let percent: Int?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            ProgressView(value: progressValue)
                .tint(progressColor)

            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressValue: Double {
        guard let percent else {
            return 0
        }

        return Double(percent) / 100
    }

    private var progressColor: Color {
        guard let percent else {
            return .secondary
        }

        if percent <= 10 {
            return .red
        }

        if percent <= 25 {
            return .orange
        }

        return .green
    }
}

private struct MetricWidgetItem: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

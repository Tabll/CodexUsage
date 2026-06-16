import SwiftUI

struct MenuBarContentView: View {
    let snapshot: UsageSnapshot?
    let status: UsageServiceStatus
    let providerName: String
    let lastErrorMessage: String?
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
                    caption: "tokens",
                    systemImage: "bolt.horizontal"
                )

                MetricTile(
                    title: "今日用量",
                    value: todayText,
                    caption: "tokens",
                    systemImage: "chart.bar.xaxis"
                )
            }

            VStack(spacing: 8) {
                InfoRow(
                    title: "状态",
                    value: status.title,
                    systemImage: status.menuBarSystemImage
                )

                InfoRow(
                    title: "预算",
                    value: budgetText,
                    systemImage: "gauge"
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

    private var budgetText: String {
        UsageFormatting.percent(snapshot?.budgetPercent)
    }

    private var estimatedCostText: String {
        UsageFormatting.cost(snapshot?.estimatedCost)
    }

    private var lastUpdatedText: String {
        UsageFormatting.time(snapshot?.updatedAt)
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
        case .failed:
            return .red
        }
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

#Preview {
    MenuBarContentView(
        snapshot: .preview,
        status: .current,
        providerName: "Codex 桌面端（Mock）",
        lastErrorMessage: nil,
        onRefresh: {},
        onQuit: {}
    )
    .frame(width: 320)
}


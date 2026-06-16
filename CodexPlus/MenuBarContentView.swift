import Foundation
import SwiftUI

struct PlaceholderUsage: Equatable {
    let currentSessionTokens: Int
    let todayTokens: Int
    let budgetPercent: Int
    let providerName: String
    let lastUpdated: Date

    static let sample = PlaceholderUsage(
        currentSessionTokens: 12_420,
        todayTokens: 58_940,
        budgetPercent: 41,
        providerName: "Codex 桌面端",
        lastUpdated: Date()
    )

    var menuBarTitle: String {
        Self.formatTokens(currentSessionTokens)
    }

    var currentSessionText: String {
        Self.formatTokens(currentSessionTokens)
    }

    var todayText: String {
        Self.formatTokens(todayTokens)
    }

    var budgetText: String {
        "\(budgetPercent)%"
    }

    var lastUpdatedText: String {
        Self.timeFormatter.string(from: lastUpdated)
    }

    func refreshed() -> PlaceholderUsage {
        let increment = Int.random(in: 180...1_200)

        return PlaceholderUsage(
            currentSessionTokens: currentSessionTokens + increment,
            todayTokens: todayTokens + increment,
            budgetPercent: min(budgetPercent + 1, 100),
            providerName: providerName,
            lastUpdated: Date()
        )
    }

    private static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }

        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }

        return "\(value)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

struct MenuBarContentView: View {
    let usage: PlaceholderUsage
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            HStack(spacing: 10) {
                MetricTile(
                    title: "当前会话",
                    value: usage.currentSessionText,
                    caption: "tokens",
                    systemImage: "bolt.horizontal"
                )

                MetricTile(
                    title: "今日用量",
                    value: usage.todayText,
                    caption: "tokens",
                    systemImage: "chart.bar.xaxis"
                )
            }

            VStack(spacing: 8) {
                InfoRow(
                    title: "预算",
                    value: usage.budgetText,
                    systemImage: "gauge"
                )

                InfoRow(
                    title: "数据源",
                    value: usage.providerName,
                    systemImage: "desktopcomputer"
                )

                InfoRow(
                    title: "更新时间",
                    value: usage.lastUpdatedText,
                    systemImage: "clock"
                )
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

            Text("占位数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
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
        usage: .sample,
        onRefresh: {},
        onQuit: {}
    )
    .frame(width: 320)
}

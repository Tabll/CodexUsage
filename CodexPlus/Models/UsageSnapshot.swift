import Foundation

struct UsageSnapshot: Equatable, Identifiable {
    let sessionId: String
    let providerName: String
    let updatedAt: Date
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let reasoningTokens: Int
    let todayTotalTokens: Int
    let estimatedCost: Decimal?
    let budgetLimitTokens: Int?

    var id: String {
        sessionId
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cachedInputTokens + reasoningTokens
    }

    var budgetPercent: Int? {
        guard let budgetLimitTokens, budgetLimitTokens > 0 else {
            return nil
        }

        let percentage = (Double(todayTotalTokens) / Double(budgetLimitTokens)) * 100
        return min(Int(percentage.rounded()), 999)
    }

    static var preview: UsageSnapshot {
        UsageSnapshot(
            sessionId: "preview-codex-desktop-session",
            providerName: "Codex 桌面端（Mock）",
            updatedAt: Date(),
            inputTokens: 7_200,
            outputTokens: 3_100,
            cachedInputTokens: 1_600,
            reasoningTokens: 520,
            todayTotalTokens: 58_940,
            estimatedCost: Decimal(string: "0.0325"),
            budgetLimitTokens: 150_000
        )
    }
}

enum UsageFormatting {
    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }

        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }

        return "\(value)"
    }

    static func percent(_ value: Int?) -> String {
        guard let value else {
            return "未设置"
        }

        return "\(value)%"
    }

    static func cost(_ value: Decimal?) -> String {
        guard let value else {
            return "未估算"
        }

        let number = NSDecimalNumber(decimal: value)
        return costFormatter.string(from: number) ?? "$\(number)"
    }

    static func time(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }

        return timeFormatter.string(from: date)
    }

    private static let costFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 4
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

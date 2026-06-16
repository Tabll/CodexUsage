import Foundation

struct UsageSnapshot: Equatable, Identifiable {
    let sessionId: String
    let providerName: String
    let updatedAt: Date
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let todayTotalTokens: Int
    let estimatedCost: Decimal?
    let budgetLimitTokens: Int?
    let rateLimits: UsageRateLimitSnapshot?

    var id: String {
        sessionId
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
            totalTokens: 10_300,
            todayTotalTokens: 58_940,
            estimatedCost: Decimal(string: "0.0325"),
            budgetLimitTokens: 150_000,
            rateLimits: .preview
        )
    }
}

struct UsageRateLimitSnapshot: Equatable {
    let planType: String?
    let updatedAt: Date
    let allowed: Bool
    let limitReached: Bool
    let shortWindow: UsageRateLimitWindow?
    let weeklyWindow: UsageRateLimitWindow?
    let monthlyWindow: UsageRateLimitWindow?

    static var preview: UsageRateLimitSnapshot {
        UsageRateLimitSnapshot(
            planType: "prolite",
            updatedAt: Date(),
            allowed: true,
            limitReached: false,
            shortWindow: UsageRateLimitWindow(
                usedPercent: 41,
                windowMinutes: 300,
                resetAfterSeconds: 2_335,
                resetAt: Date().addingTimeInterval(2_335)
            ),
            weeklyWindow: UsageRateLimitWindow(
                usedPercent: 56,
                windowMinutes: 10_080,
                resetAfterSeconds: 118_153,
                resetAt: Date().addingTimeInterval(118_153)
            ),
            monthlyWindow: nil
        )
    }
}

struct UsageRateLimitWindow: Equatable {
    let usedPercent: Int
    let windowMinutes: Int
    let resetAfterSeconds: Int?
    let resetAt: Date?

    var remainingPercent: Int {
        min(max(100 - usedPercent, 0), 100)
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

    static func remainingPercent(_ window: UsageRateLimitWindow?) -> String {
        guard let window else {
            return "--"
        }

        return "\(window.remainingPercent)%"
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

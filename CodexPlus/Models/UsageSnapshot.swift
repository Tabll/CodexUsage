import Foundation

struct UsageSnapshot: Codable, Equatable, Identifiable {
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

    func withBudgetLimitTokens(_ budgetLimitTokens: Int?) -> UsageSnapshot {
        UsageSnapshot(
            sessionId: sessionId,
            providerName: providerName,
            updatedAt: updatedAt,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedInputTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: totalTokens,
            todayTotalTokens: todayTotalTokens,
            estimatedCost: estimatedCost,
            budgetLimitTokens: budgetLimitTokens,
            rateLimits: rateLimits
        )
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

struct UsageRateLimitSnapshot: Codable, Equatable {
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

struct UsageRateLimitWindow: Codable, Equatable {
    let usedPercent: Int
    let windowMinutes: Int
    let resetAfterSeconds: Int?
    let resetAt: Date?

    var remainingPercent: Int {
        min(max(100 - usedPercent, 0), 100)
    }
}

struct UsageBudgetConfiguration: Codable, Equatable {
    static let defaultDailyLimitTokens = 150_000
    static let defaultWarningThresholdPercent = 80
    static let minimumDailyLimitTokens = 1_000
    static let maximumDailyLimitTokens = 100_000_000
    static let minimumWarningThresholdPercent = 1
    static let maximumWarningThresholdPercent = 100

    let isEnabled: Bool
    let dailyLimitTokens: Int
    let warningThresholdPercent: Int
    let notificationsEnabled: Bool

    init(
        isEnabled: Bool,
        dailyLimitTokens: Int = Self.defaultDailyLimitTokens,
        warningThresholdPercent: Int = Self.defaultWarningThresholdPercent,
        notificationsEnabled: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.dailyLimitTokens = Self.clampedDailyLimitTokens(dailyLimitTokens)
        self.warningThresholdPercent = Self.clampedWarningThresholdPercent(warningThresholdPercent)
        self.notificationsEnabled = notificationsEnabled
    }

    static var disabled: UsageBudgetConfiguration {
        UsageBudgetConfiguration(isEnabled: false)
    }

    static func clampedDailyLimitTokens(_ value: Int) -> Int {
        min(max(value, minimumDailyLimitTokens), maximumDailyLimitTokens)
    }

    static func clampedWarningThresholdPercent(_ value: Int) -> Int {
        min(max(value, minimumWarningThresholdPercent), maximumWarningThresholdPercent)
    }
}

enum UsageBudgetSeverity: Int, Equatable {
    case disabled
    case normal
    case warning
    case exceeded

    var isNotifiable: Bool {
        self == .warning || self == .exceeded
    }
}

struct UsageBudgetState: Equatable {
    let configuration: UsageBudgetConfiguration
    let usedTokens: Int

    init(configuration: UsageBudgetConfiguration, usedTokens: Int) {
        self.configuration = configuration
        self.usedTokens = max(usedTokens, 0)
    }

    static var disabled: UsageBudgetState {
        UsageBudgetState(configuration: .disabled, usedTokens: 0)
    }

    var dailyLimitTokens: Int? {
        configuration.isEnabled ? configuration.dailyLimitTokens : nil
    }

    var usedPercent: Int? {
        guard let dailyLimitTokens, dailyLimitTokens > 0 else {
            return nil
        }

        let percentage = (Double(usedTokens) / Double(dailyLimitTokens)) * 100
        return min(Int(percentage.rounded()), 999)
    }

    var remainingTokens: Int? {
        guard let dailyLimitTokens else {
            return nil
        }

        return max(dailyLimitTokens - usedTokens, 0)
    }

    var warningLimitTokens: Int? {
        guard let dailyLimitTokens else {
            return nil
        }

        let threshold = Double(configuration.warningThresholdPercent) / 100
        return Int((Double(dailyLimitTokens) * threshold).rounded())
    }

    var severity: UsageBudgetSeverity {
        guard let dailyLimitTokens else {
            return .disabled
        }

        if usedTokens >= dailyLimitTokens {
            return .exceeded
        }

        if let warningLimitTokens, usedTokens >= warningLimitTokens {
            return .warning
        }

        return .normal
    }

    var title: String {
        switch severity {
        case .disabled:
            return "未开启"
        case .normal:
            return "正常"
        case .warning:
            return "接近预算"
        case .exceeded:
            return "已超预算"
        }
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

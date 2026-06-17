import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case rateLimitSummary
    case currentSessionTokens
    case todayTokens
    case shortWindowRemaining
    case weeklyWindowRemaining
    case budgetPercent
    case estimatedCost

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .rateLimitSummary:
            return "5 小时 + 本周"
        case .currentSessionTokens:
            return "当前会话"
        case .todayTokens:
            return "今日用量"
        case .shortWindowRemaining:
            return "5 小时剩余"
        case .weeklyWindowRemaining:
            return "每周剩余"
        case .budgetPercent:
            return "预算比例"
        case .estimatedCost:
            return "预估花费"
        }
    }

    var systemImage: String {
        switch self {
        case .rateLimitSummary:
            return "menubar.rectangle"
        case .currentSessionTokens:
            return "bolt.horizontal.circle.fill"
        case .todayTokens:
            return "chart.bar.xaxis"
        case .shortWindowRemaining:
            return "hourglass"
        case .weeklyWindowRemaining:
            return "calendar"
        case .budgetPercent:
            return "gauge"
        case .estimatedCost:
            return "creditcard"
        }
    }

    func menuBarTitle(for snapshot: UsageSnapshot?, status: UsageServiceStatus) -> String {
        if case .failed = status {
            return "错误"
        }

        guard let snapshot else {
            if self == .rateLimitSummary {
                return UsageFormatting.rateLimitSummary(nil)
            }

            return "Codex用量"
        }

        switch self {
        case .rateLimitSummary:
            return UsageFormatting.rateLimitSummary(snapshot.rateLimits)
        case .currentSessionTokens:
            return UsageFormatting.tokens(snapshot.totalTokens)
        case .todayTokens:
            return UsageFormatting.tokens(snapshot.todayTotalTokens)
        case .shortWindowRemaining:
            return UsageFormatting.remainingPercent(snapshot.rateLimits?.shortWindow)
        case .weeklyWindowRemaining:
            return UsageFormatting.remainingPercent(snapshot.rateLimits?.weeklyWindow)
        case .budgetPercent:
            return UsageFormatting.percent(snapshot.budgetPercent)
        case .estimatedCost:
            return UsageFormatting.cost(snapshot.estimatedCost)
        }
    }
}

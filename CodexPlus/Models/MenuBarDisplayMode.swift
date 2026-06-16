import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case currentSessionTokens
    case todayTokens
    case budgetPercent
    case estimatedCost

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .currentSessionTokens:
            return "当前会话"
        case .todayTokens:
            return "今日用量"
        case .budgetPercent:
            return "预算比例"
        case .estimatedCost:
            return "预估花费"
        }
    }

    var systemImage: String {
        switch self {
        case .currentSessionTokens:
            return "bolt.horizontal.circle.fill"
        case .todayTokens:
            return "chart.bar.xaxis"
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
            return "CodexPlus"
        }

        switch self {
        case .currentSessionTokens:
            return UsageFormatting.tokens(snapshot.totalTokens)
        case .todayTokens:
            return UsageFormatting.tokens(snapshot.todayTotalTokens)
        case .budgetPercent:
            return UsageFormatting.percent(snapshot.budgetPercent)
        case .estimatedCost:
            return UsageFormatting.cost(snapshot.estimatedCost)
        }
    }
}


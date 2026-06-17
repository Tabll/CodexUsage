import Foundation

enum UsageDataSourceMode: String, CaseIterable, Codable, Identifiable {
    case codexDesktop
    case mock

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .codexDesktop:
            return "Codex 桌面端"
        case .mock:
            return "Mock 数据"
        }
    }

    var systemImage: String {
        switch self {
        case .codexDesktop:
            return "desktopcomputer"
        case .mock:
            return "wand.and.stars"
        }
    }
}

protocol UsageProvider {
    var name: String { get }
    var refreshHintFiles: [URL] { get }

    func fetchSnapshot() async throws -> UsageSnapshot
}

protocol UsageHistoryProvider {
    func fetchDailyUsageHistory(days: Int) async throws -> [DailyUsageSummary]
}

protocol UsageLatestMessageProvider {
    func fetchLatestLogMessage() async throws -> CodexLogMessage
}

extension UsageProvider {
    var refreshHintFiles: [URL] {
        []
    }
}

enum UsageProviderError: LocalizedError, Equatable {
    case unavailable(String)
    case malformedData(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .malformedData(let message):
            return message
        }
    }
}

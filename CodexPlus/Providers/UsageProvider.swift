import Foundation

protocol UsageProvider {
    var name: String { get }
    var refreshHintFiles: [URL] { get }

    func fetchSnapshot() async throws -> UsageSnapshot
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

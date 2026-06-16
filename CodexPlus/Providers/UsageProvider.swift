import Foundation

protocol UsageProvider {
    var name: String { get }

    func fetchSnapshot() async throws -> UsageSnapshot
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


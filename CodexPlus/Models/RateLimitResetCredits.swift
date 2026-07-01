import Foundation

struct RateLimitResetCreditsSnapshot: Codable, Equatable {
    static let defaultRefreshInterval: TimeInterval = 24 * 60 * 60
    static let maximumDisplayedCreditCount = 3

    let availableCount: Int
    let credits: [RateLimitResetCredit]
    let updatedAt: Date

    var nearestExpiringCredits: [RateLimitResetCredit] {
        let sortedCredits = credits.sorted { lhs, rhs in
            switch (lhs.expiresAt, rhs.expiresAt) {
            case let (lhsExpiresAt?, rhsExpiresAt?):
                return lhsExpiresAt < rhsExpiresAt
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return false
            }
        }

        return Array(sortedCredits.prefix(Self.maximumDisplayedCreditCount))
    }

    static var preview: RateLimitResetCreditsSnapshot {
        RateLimitResetCreditsSnapshot(
            availableCount: 2,
            credits: [
                RateLimitResetCredit(
                    status: "available",
                    title: "Reset credit",
                    grantedAt: Date().addingTimeInterval(-3_600),
                    expiresAt: Date().addingTimeInterval(86_400)
                ),
                RateLimitResetCredit(
                    status: "available",
                    title: "Reset credit",
                    grantedAt: Date().addingTimeInterval(-1_800),
                    expiresAt: Date().addingTimeInterval(172_800)
                )
            ],
            updatedAt: Date()
        )
    }
}

struct RateLimitResetCredit: Codable, Equatable {
    let status: String
    let title: String
    let grantedAt: Date?
    let expiresAt: Date?

    var localizedStatusTitle: String {
        switch status.lowercased() {
        case "available":
            return "可用"
        default:
            return status
        }
    }
}

enum RateLimitResetCreditsStatus: Equatable {
    case idle
    case refreshing
    case current
    case stale
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "等待数据"
        case .refreshing:
            return "刷新中"
        case .current:
            return "正常"
        case .stale:
            return "数据过期"
        case .failed:
            return "错误"
        }
    }
}

enum RateLimitResetCreditsError: LocalizedError, Equatable {
    case missingCredentials
    case missingAccessToken
    case unauthorized
    case invalidResponse
    case httpStatus(Int)
    case malformedData(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "找不到 Codex 凭证：~/.codex/auth.json"
        case .missingAccessToken:
            return "Codex 凭证中没有 tokens.access_token"
        case .unauthorized:
            return "Codex 凭证失效，或请求缺少 Authorization header"
        case .invalidResponse:
            return "reset credits 响应无效"
        case .httpStatus(let statusCode):
            return "reset credits 请求失败（HTTP \(statusCode)）"
        case .malformedData(let message):
            return message
        }
    }
}

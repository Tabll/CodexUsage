import Combine
import Foundation

protocol RateLimitResetCreditsProvider {
    func fetchResetCredits() async throws -> RateLimitResetCreditsSnapshot
}

@MainActor
final class RateLimitResetCreditsService: ObservableObject {
    @Published private(set) var snapshot: RateLimitResetCreditsSnapshot?
    @Published private(set) var status: RateLimitResetCreditsStatus = .idle
    @Published private(set) var lastErrorMessage: String?

    private let provider: any RateLimitResetCreditsProvider
    private let cache: RateLimitResetCreditsCache
    private let refreshInterval: TimeInterval
    private var isRefreshing = false

    init(
        provider: any RateLimitResetCreditsProvider = ChatGPTRateLimitResetCreditsProvider(),
        cache: RateLimitResetCreditsCache = RateLimitResetCreditsCache(),
        refreshInterval: TimeInterval = RateLimitResetCreditsSnapshot.defaultRefreshInterval,
        startsImmediately: Bool = true
    ) {
        self.provider = provider
        self.cache = cache
        self.refreshInterval = refreshInterval

        if let cachedSnapshot = cache.cachedSnapshot() {
            snapshot = cachedSnapshot
            status = isSnapshotStale(cachedSnapshot) ? .stale : .current
        }

        if startsImmediately {
            refreshIfNeeded()
        }
    }

    func refreshIfNeeded() {
        Task { [weak self] in
            await self?.refreshNow(force: false)
        }
    }

    func refresh() {
        Task { [weak self] in
            await self?.refreshNow(force: true)
        }
    }

    func refreshNow(force: Bool = true) async {
        guard !isRefreshing else {
            return
        }

        if !force,
           let snapshot,
           !isSnapshotStale(snapshot) {
            return
        }

        if !force,
           let lastFetchAttemptAt = cache.lastFetchAttemptAt(),
           !isDateStale(lastFetchAttemptAt) {
            return
        }

        isRefreshing = true
        status = .refreshing

        defer {
            isRefreshing = false
        }

        do {
            cache.saveFetchAttempt(at: Date())
            let nextSnapshot = try await provider.fetchResetCredits()

            snapshot = nextSnapshot
            status = .current
            lastErrorMessage = nil
            cache.saveSnapshot(nextSnapshot)
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            status = .failed(message)
        }
    }

    private func isSnapshotStale(_ snapshot: RateLimitResetCreditsSnapshot) -> Bool {
        Date().timeIntervalSince(snapshot.updatedAt) >= refreshInterval
    }

    private func isDateStale(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) >= refreshInterval
    }
}

struct ChatGPTRateLimitResetCreditsProvider: RateLimitResetCreditsProvider {
    private let authURL: URL
    private let endpointURL: URL
    private let session: URLSession

    init(
        authURL: URL = Self.defaultAuthURL(),
        endpointURL: URL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
        session: URLSession = .shared
    ) {
        self.authURL = authURL
        self.endpointURL = endpointURL
        self.session = session
    }

    func fetchResetCredits() async throws -> RateLimitResetCreditsSnapshot {
        let accessToken = try loadAccessToken()
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RateLimitResetCreditsError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw RateLimitResetCreditsError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RateLimitResetCreditsError.httpStatus(httpResponse.statusCode)
        }

        return try RateLimitResetCreditsParser.parse(data)
    }

    private func loadAccessToken() throws -> String {
        guard FileManager.default.isReadableFile(atPath: authURL.path) else {
            throw RateLimitResetCreditsError.missingCredentials
        }

        let data = try Data(contentsOf: authURL)
        let object = try JSONSerialization.jsonObject(with: data)

        guard let root = object as? [String: Any],
              let tokens = root["tokens"] as? [String: Any] else {
            throw RateLimitResetCreditsError.missingAccessToken
        }

        guard let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else {
            throw RateLimitResetCreditsError.missingAccessToken
        }

        return accessToken
    }

    private static func defaultAuthURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
    }
}

enum RateLimitResetCreditsParser {
    static func parse(_ data: Data, updatedAt: Date = Date()) throws -> RateLimitResetCreditsSnapshot {
        let object = try JSONSerialization.jsonObject(with: data)

        guard let root = object as? [String: Any] else {
            throw RateLimitResetCreditsError.malformedData("reset credits 响应不是 JSON 对象")
        }

        let payload = payloadDictionary(from: root)
        let credits = creditDictionaries(from: payload).map(parseCredit)
        let availableCount = intValue(payload["available_count"])
            ?? intValue(payload["availableCount"])
            ?? credits.filter { $0.status.lowercased() == "available" }.count

        guard payload["available_count"] != nil || payload["availableCount"] != nil || !credits.isEmpty else {
            throw RateLimitResetCreditsError.malformedData("reset credits 响应缺少 available_count 和 credits")
        }

        return RateLimitResetCreditsSnapshot(
            availableCount: availableCount,
            credits: credits,
            updatedAt: updatedAt
        )
    }

    private static func payloadDictionary(from root: [String: Any]) -> [String: Any] {
        if let data = root["data"] as? [String: Any] {
            return data
        }

        if let result = root["result"] as? [String: Any] {
            return result
        }

        return root
    }

    private static func creditDictionaries(from payload: [String: Any]) -> [[String: Any]] {
        if let credits = payload["credits"] as? [[String: Any]] {
            return credits
        }

        if let items = payload["items"] as? [[String: Any]] {
            return items
        }

        return []
    }

    private static func parseCredit(_ value: [String: Any]) -> RateLimitResetCredit {
        RateLimitResetCredit(
            status: stringValue(value["status"]),
            title: stringValue(value["title"]),
            grantedAt: dateValue(value["granted_at"]),
            expiresAt: dateValue(value["expires_at"])
        )
    }

    private static func stringValue(_ value: Any?) -> String {
        if let value = value as? String {
            return value
        }

        if let value = value as? NSNumber {
            return value.stringValue
        }

        return "--"
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        if let value = value as? String {
            return Int(value)
        }

        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? String {
            return fractionalISO8601Formatter.date(from: value)
                ?? plainISO8601Formatter.date(from: value)
        }

        if let value = value as? NSNumber {
            let rawValue = value.doubleValue
            let seconds = rawValue > 10_000_000_000 ? rawValue / 1_000 : rawValue
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct RateLimitResetCreditsCache {
    private let defaults: UserDefaults
    private let snapshotKey: String
    private let lastFetchAttemptAtKey: String

    init(
        defaults: UserDefaults = .standard,
        snapshotKey: String = "rateLimitResetCreditsSnapshot",
        lastFetchAttemptAtKey: String = "rateLimitResetCreditsLastFetchAttemptAt"
    ) {
        self.defaults = defaults
        self.snapshotKey = snapshotKey
        self.lastFetchAttemptAtKey = lastFetchAttemptAtKey
    }

    func cachedSnapshot() -> RateLimitResetCreditsSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(RateLimitResetCreditsSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: RateLimitResetCreditsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: snapshotKey)
    }

    func lastFetchAttemptAt() -> Date? {
        defaults.object(forKey: lastFetchAttemptAtKey) as? Date
    }

    func saveFetchAttempt(at date: Date) {
        defaults.set(date, forKey: lastFetchAttemptAtKey)
    }
}

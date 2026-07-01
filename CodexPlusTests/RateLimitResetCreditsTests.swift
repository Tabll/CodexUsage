import XCTest

final class RateLimitResetCreditsTests: XCTestCase {
    func testParserReadsAvailableCountCreditsAndUTCDates() throws {
        let data = Data(
            """
            {
              "available_count": 2,
              "credits": [
                {
                  "id": "not-used-in-model",
                  "status": "available",
                  "title": "Reset credit",
                  "granted_at": "2026-07-01T10:15:30Z",
                  "expires_at": "2026-07-02T10:15:30.250Z"
                }
              ]
            }
            """.utf8
        )
        let updatedAt = Date(timeIntervalSince1970: 123)

        let snapshot = try RateLimitResetCreditsParser.parse(data, updatedAt: updatedAt)

        XCTAssertEqual(snapshot.availableCount, 2)
        XCTAssertEqual(snapshot.updatedAt, updatedAt)
        XCTAssertEqual(snapshot.credits.count, 1)
        XCTAssertEqual(snapshot.credits[0].status, "available")
        XCTAssertEqual(snapshot.credits[0].title, "Reset credit")
        XCTAssertEqual(
            snapshot.credits[0].grantedAt,
            ISO8601DateFormatter().date(from: "2026-07-01T10:15:30Z")
        )
        XCTAssertEqual(
            snapshot.credits[0].expiresAt,
            fractionalISO8601Formatter.date(from: "2026-07-02T10:15:30.250Z")
        )
    }

    func testAvailableStatusDisplaysInChinese() {
        let credit = RateLimitResetCredit(
            status: "available",
            title: "Reset credit",
            grantedAt: nil,
            expiresAt: nil
        )

        XCTAssertEqual(credit.localizedStatusTitle, "可用")
    }

    func testSnapshotLimitsDetailRowsToThreeNearestExpiringCredits() {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        let snapshot = RateLimitResetCreditsSnapshot(
            availableCount: 4,
            credits: [
                makeCredit(title: "第四", expiresAt: baseDate.addingTimeInterval(400)),
                makeCredit(title: "第二", expiresAt: baseDate.addingTimeInterval(200)),
                makeCredit(title: "第一", expiresAt: baseDate.addingTimeInterval(100)),
                makeCredit(title: "第三", expiresAt: baseDate.addingTimeInterval(300))
            ],
            updatedAt: baseDate
        )

        XCTAssertEqual(
            snapshot.nearestExpiringCredits.map(\.title),
            ["第一", "第二", "第三"]
        )
    }

    @MainActor
    func testServiceSkipsFreshCachedSnapshotWhenRefreshIsNotForced() async {
        let suiteName = "CodexPlusTests.ResetCredits.FreshCache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let cachedSnapshot = makeSnapshot(availableCount: 1, updatedAt: Date())
        let cache = RateLimitResetCreditsCache(defaults: defaults)
        cache.saveSnapshot(cachedSnapshot)
        let provider = CountingResetCreditsProvider(result: .success(makeSnapshot(availableCount: 3)))
        let service = RateLimitResetCreditsService(
            provider: provider,
            cache: cache,
            startsImmediately: false
        )

        await service.refreshNow(force: false)

        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertEqual(service.snapshot?.availableCount, 1)
        XCTAssertEqual(service.status, .current)
    }

    @MainActor
    func testServiceManualRefreshBypassesFreshCache() async {
        let suiteName = "CodexPlusTests.ResetCredits.Manual.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let cache = RateLimitResetCreditsCache(defaults: defaults)
        cache.saveSnapshot(makeSnapshot(availableCount: 1, updatedAt: Date()))
        let provider = CountingResetCreditsProvider(result: .success(makeSnapshot(availableCount: 4)))
        let service = RateLimitResetCreditsService(
            provider: provider,
            cache: cache,
            startsImmediately: false
        )

        await service.refreshNow(force: true)

        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(service.snapshot?.availableCount, 4)
        XCTAssertEqual(cache.cachedSnapshot()?.availableCount, 4)
        XCTAssertEqual(service.status, .current)
    }

    @MainActor
    func testServiceThrottlesAutomaticRetryAfterFailedAttempt() async {
        let suiteName = "CodexPlusTests.ResetCredits.FailureThrottle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let provider = CountingResetCreditsProvider(result: .failure(RateLimitResetCreditsError.unauthorized))
        let service = RateLimitResetCreditsService(
            provider: provider,
            cache: RateLimitResetCreditsCache(defaults: defaults),
            startsImmediately: false
        )

        await service.refreshNow(force: false)
        await service.refreshNow(force: false)

        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(
            service.lastErrorMessage,
            "Codex 凭证失效，或请求缺少 Authorization header"
        )
    }

    @MainActor
    func testServiceReportsUnauthorizedCredentials() async {
        let provider = CountingResetCreditsProvider(result: .failure(RateLimitResetCreditsError.unauthorized))
        let service = RateLimitResetCreditsService(provider: provider, startsImmediately: false)

        await service.refreshNow(force: true)

        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(
            service.lastErrorMessage,
            "Codex 凭证失效，或请求缺少 Authorization header"
        )
        XCTAssertEqual(
            service.status,
            .failed("Codex 凭证失效，或请求缺少 Authorization header")
        )
    }

    private func makeSnapshot(
        availableCount: Int,
        updatedAt: Date = Date()
    ) -> RateLimitResetCreditsSnapshot {
        RateLimitResetCreditsSnapshot(
            availableCount: availableCount,
            credits: [
                RateLimitResetCredit(
                    status: "available",
                    title: "Reset credit",
                    grantedAt: Date(timeIntervalSince1970: 100),
                    expiresAt: Date(timeIntervalSince1970: 200)
                )
            ],
            updatedAt: updatedAt
        )
    }

    private func makeCredit(
        title: String,
        expiresAt: Date
    ) -> RateLimitResetCredit {
        RateLimitResetCredit(
            status: "available",
            title: title,
            grantedAt: Date(timeIntervalSince1970: 100),
            expiresAt: expiresAt
        )
    }

    private var fractionalISO8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private final class CountingResetCreditsProvider: RateLimitResetCreditsProvider {
    private let result: Result<RateLimitResetCreditsSnapshot, Error>
    private(set) var fetchCount = 0

    init(result: Result<RateLimitResetCreditsSnapshot, Error>) {
        self.result = result
    }

    func fetchResetCredits() async throws -> RateLimitResetCreditsSnapshot {
        fetchCount += 1
        return try result.get()
    }
}

import XCTest

@MainActor
final class UsageServiceTests: XCTestCase {
    func testDefaultRefreshCadenceUsesProductionIntervals() {
        XCTAssertTrue(UsageServiceRefreshDefaults.isIdlePollingEnabled)
        XCTAssertEqual(UsageServiceRefreshDefaults.idleRefreshInterval, 30 * 60)
        XCTAssertEqual(UsageServiceRefreshDefaults.fileChangeDebounceInterval, 5)
        XCTAssertEqual(UsageServiceRefreshDefaults.activeRefreshInterval, 20)
    }

    func testRefreshPublishesSnapshotAndCallsCacheHook() async throws {
        let snapshot = makeSnapshot(todayTotalTokens: 50_000)
        var cachedSnapshot: UsageSnapshot?
        let service = UsageService(
            provider: FixedUsageProvider(result: .success(snapshot)),
            budgetConfiguration: UsageBudgetConfiguration(
                isEnabled: true,
                dailyLimitTokens: 100_000,
                warningThresholdPercent: 80
            ),
            onSnapshotUpdate: { snapshot in
                cachedSnapshot = snapshot
            },
            startsImmediately: false
        )

        await service.refreshNow()

        XCTAssertEqual(service.snapshot?.todayTotalTokens, 50_000)
        XCTAssertEqual(service.snapshot?.budgetLimitTokens, 100_000)
        XCTAssertEqual(service.status, .current)
        XCTAssertEqual(service.budgetState.severity, .normal)
        XCTAssertEqual(cachedSnapshot?.todayTotalTokens, 50_000)
    }

    func testRefreshReportsProviderFailure() async {
        let service = UsageService(
            provider: FixedUsageProvider(result: .failure(.unavailable("missing fixture"))),
            startsImmediately: false
        )

        await service.refreshNow()

        XCTAssertEqual(service.status, .failed("missing fixture"))
        XCTAssertEqual(service.lastErrorMessage, "missing fixture")
        XCTAssertNil(service.snapshot)
    }

    func testStaleStatusAfterInterval() async throws {
        let service = UsageService(
            provider: FixedUsageProvider(result: .success(makeSnapshot())),
            refreshConfiguration: UsageRefreshConfiguration(
                isIdlePollingEnabled: false,
                idleRefreshInterval: 0.01
            ),
            startsImmediately: false
        )

        await service.refreshNow()
        XCTAssertEqual(service.status, .current)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(service.status, .stale)
    }

    func testCachedSnapshotRestoresStaleStateBeforeRefresh() {
        let service = UsageService(
            provider: FixedUsageProvider(result: .success(makeSnapshot())),
            budgetConfiguration: UsageBudgetConfiguration(
                isEnabled: true,
                dailyLimitTokens: 100_000,
                warningThresholdPercent: 80
            ),
            cachedSnapshot: makeSnapshot(todayTotalTokens: 90_000),
            startsImmediately: false
        )

        XCTAssertEqual(service.snapshot?.todayTotalTokens, 90_000)
        XCTAssertEqual(service.snapshot?.budgetLimitTokens, 100_000)
        XCTAssertEqual(service.status, .stale)
        XCTAssertEqual(service.budgetState.severity, .warning)
    }

    func testAutomaticRefreshesRespectMinimumInterval() async throws {
        let provider = CountingUsageProvider(snapshot: makeSnapshot())
        let service = UsageService(
            provider: provider,
            refreshConfiguration: UsageRefreshConfiguration(
                isIdlePollingEnabled: false,
                activeRefreshInterval: 0.15
            ),
            startsImmediately: false
        )

        service.refreshAutomatically()
        try await waitForFetchCount(1, provider: provider)

        service.refreshAutomatically()
        service.refreshAutomatically()

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(provider.fetchCount, 1)

        try await waitForFetchCount(2, provider: provider)
        XCTAssertEqual(provider.fetchCount, 2)
    }

    func testManualRefreshBypassesAutomaticMinimumInterval() async {
        let provider = CountingUsageProvider(snapshot: makeSnapshot())
        let service = UsageService(
            provider: provider,
            refreshConfiguration: UsageRefreshConfiguration(
                isIdlePollingEnabled: false,
                activeRefreshInterval: 5
            ),
            startsImmediately: false
        )

        await service.refreshNow()
        await service.refreshNow()

        XCTAssertEqual(provider.fetchCount, 2)
    }

    func testRefreshKeepsCurrentSnapshotWhenProviderReturnsOlderData() async {
        let newerSnapshot = makeSnapshot(
            updatedAt: Date(timeIntervalSince1970: 200),
            todayTotalTokens: 20_000
        )
        let olderSnapshot = makeSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            todayTotalTokens: 10_000
        )
        let provider = SequenceUsageProvider(snapshots: [newerSnapshot, olderSnapshot])
        let service = UsageService(provider: provider, startsImmediately: false)

        await service.refreshNow()
        await service.refreshNow()

        XCTAssertEqual(service.snapshot?.updatedAt, newerSnapshot.updatedAt)
        XCTAssertEqual(service.snapshot?.todayTotalTokens, 20_000)
        XCTAssertEqual(service.status, .current)
    }

    func testDisabledIdlePollingOnlyRefreshesOnStart() async throws {
        let provider = CountingUsageProvider(snapshot: makeSnapshot())
        let service = UsageService(
            provider: provider,
            refreshConfiguration: UsageRefreshConfiguration(
                isIdlePollingEnabled: false,
                idleRefreshInterval: 0.02,
                activeRefreshInterval: 0.02
            )
        )

        try await waitForFetchCount(1, provider: provider)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(provider.fetchCount, 1)
        service.stop()
    }

    private func makeSnapshot(
        updatedAt: Date = Date(),
        todayTotalTokens: Int = 42_000
    ) -> UsageSnapshot {
        UsageSnapshot(
            sessionId: "test-session",
            providerName: "Test Provider",
            updatedAt: updatedAt,
            inputTokens: 1_000,
            outputTokens: 500,
            cachedInputTokens: 100,
            reasoningTokens: 50,
            totalTokens: 1_500,
            todayTotalTokens: todayTotalTokens,
            estimatedCost: nil,
            budgetLimitTokens: nil,
            rateLimits: nil
        )
    }

    private func waitForFetchCount(
        _ expectedCount: Int,
        provider: CountingUsageProvider,
        timeout: TimeInterval = 1
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while provider.fetchCount < expectedCount && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(provider.fetchCount, expectedCount)
    }
}

private final class SequenceUsageProvider: UsageProvider {
    private var snapshots: [UsageSnapshot]

    var name: String {
        "Sequence Provider"
    }

    init(snapshots: [UsageSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        guard !snapshots.isEmpty else {
            throw UsageProviderError.unavailable("missing snapshot")
        }

        if snapshots.count == 1 {
            return snapshots[0]
        }

        return snapshots.removeFirst()
    }
}

private struct FixedUsageProvider: UsageProvider {
    let result: Result<UsageSnapshot, UsageProviderError>

    var name: String {
        "Fixed Provider"
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }
}

private final class CountingUsageProvider: UsageProvider {
    let snapshot: UsageSnapshot
    private(set) var fetchCount = 0

    var name: String {
        "Counting Provider"
    }

    init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        fetchCount += 1
        return snapshot
    }
}

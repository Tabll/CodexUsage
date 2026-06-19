import XCTest

final class UsageModelTests: XCTestCase {
    func testBudgetPercentUsesTodayTotalAndConfiguredLimit() {
        let snapshot = UsageSnapshot.preview.withBudgetLimitTokens(120_000)

        XCTAssertEqual(snapshot.budgetPercent, 49)
    }

    func testBudgetConfigurationClampsUnsafeValues() {
        let configuration = UsageBudgetConfiguration(
            isEnabled: true,
            dailyLimitTokens: 10,
            warningThresholdPercent: 180,
            notificationsEnabled: true
        )

        XCTAssertEqual(configuration.dailyLimitTokens, UsageBudgetConfiguration.minimumDailyLimitTokens)
        XCTAssertEqual(configuration.warningThresholdPercent, UsageBudgetConfiguration.maximumWarningThresholdPercent)
        XCTAssertTrue(configuration.notificationsEnabled)
    }

    func testBudgetStateReportsWarningAndRemainingTokens() {
        let state = UsageBudgetState(
            configuration: UsageBudgetConfiguration(
                isEnabled: true,
                dailyLimitTokens: 100_000,
                warningThresholdPercent: 80
            ),
            usedTokens: 82_000
        )

        XCTAssertEqual(state.usedPercent, 82)
        XCTAssertEqual(state.remainingTokens, 18_000)
        XCTAssertEqual(state.warningLimitTokens, 80_000)
        XCTAssertEqual(state.severity, .warning)
        XCTAssertEqual(state.title, "接近预算")
    }

    func testBudgetStateReportsExceeded() {
        let state = UsageBudgetState(
            configuration: UsageBudgetConfiguration(
                isEnabled: true,
                dailyLimitTokens: 100_000,
                warningThresholdPercent: 80
            ),
            usedTokens: 120_000
        )

        XCTAssertEqual(state.usedPercent, 120)
        XCTAssertEqual(state.remainingTokens, 0)
        XCTAssertEqual(state.severity, .exceeded)
        XCTAssertEqual(state.title, "已超预算")
    }

    func testDisabledBudgetStateHasNoPercent() {
        let state = UsageBudgetState(
            configuration: .disabled,
            usedTokens: 82_000
        )

        XCTAssertNil(state.dailyLimitTokens)
        XCTAssertNil(state.usedPercent)
        XCTAssertNil(state.remainingTokens)
        XCTAssertEqual(state.severity, .disabled)
    }

    func testRateLimitSummaryMenuBarTitleUsesShortAndWeeklyRemainingPercent() {
        let title = MenuBarDisplayMode.rateLimitSummary.menuBarTitle(
            for: .preview,
            status: .current
        )

        XCTAssertEqual(title, "5小时 59% 本周 44%")
    }

    func testRateLimitSummaryMenuBarTitleKeepsShapeWithoutSnapshot() {
        let title = MenuBarDisplayMode.rateLimitSummary.menuBarTitle(
            for: nil,
            status: .idle
        )

        XCTAssertEqual(title, "5小时 -- 本周 --")
    }

    func testFallbackMenuBarTitleUsesAppDisplayName() {
        let title = MenuBarDisplayMode.todayTokens.menuBarTitle(
            for: nil,
            status: .idle
        )

        XCTAssertEqual(title, "Codex用量")
    }

    func testMonthDayTimeUsesChineseCompactDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 18, hour: 22, minute: 32)
        )

        XCTAssertEqual(UsageFormatting.monthDayTime(date), "6月18日 22:32")
        XCTAssertEqual(UsageFormatting.monthDayTime(nil), "--")
    }

    func testSharedUsageCacheSavesAndFiltersSnapshot() {
        let suiteName = "CodexPlusTests.SharedUsageCache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let cache = SharedUsageCache(defaults: defaults)
        cache.saveCachedSnapshot(.preview, dataSourceModeRawValue: UsageDataSourceMode.codexDesktop.rawValue)

        XCTAssertEqual(
            cache.cachedSnapshot(forDataSourceModeRawValue: UsageDataSourceMode.codexDesktop.rawValue)?.sessionId,
            UsageSnapshot.preview.sessionId
        )
        XCTAssertEqual(cache.cachedSnapshot()?.sessionId, UsageSnapshot.preview.sessionId)
        XCTAssertNil(cache.cachedSnapshot(forDataSourceModeRawValue: UsageDataSourceMode.mock.rawValue))
    }

    func testSharedUsageCacheMigratesLegacySnapshot() {
        let legacySuiteName = "CodexPlusTests.LegacyUsageCache.\(UUID().uuidString)"
        let sharedSuiteName = "CodexPlusTests.MigratedUsageCache.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName) ?? .standard
        let sharedDefaults = UserDefaults(suiteName: sharedSuiteName) ?? .standard
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
        defer {
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
            sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
        }

        SharedUsageCache(defaults: legacyDefaults).saveCachedSnapshot(
            .preview,
            dataSourceModeRawValue: UsageDataSourceMode.codexDesktop.rawValue
        )

        SharedUsageCache.migrateLegacySnapshotIfNeeded(
            from: legacyDefaults,
            to: sharedDefaults
        )

        XCTAssertEqual(
            SharedUsageCache(defaults: sharedDefaults)
                .cachedSnapshot(forDataSourceModeRawValue: UsageDataSourceMode.codexDesktop.rawValue)?
                .sessionId,
            UsageSnapshot.preview.sessionId
        )
    }

    @MainActor
    func testSettingsStorePersistsRefreshConfiguration() {
        let suiteName = "CodexPlusTests.RefreshConfiguration"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.refreshConfiguration.isIdlePollingEnabled)
        XCTAssertEqual(store.refreshConfiguration.idleRefreshInterval, 30 * 60)
        XCTAssertEqual(store.refreshConfiguration.activeRefreshInterval, 20)

        store.isIdlePollingEnabled = false
        store.idleRefreshIntervalMinutes = 45
        store.activeRefreshIntervalSeconds = 35

        let restoredStore = SettingsStore(defaults: defaults)
        XCTAssertFalse(restoredStore.refreshConfiguration.isIdlePollingEnabled)
        XCTAssertEqual(restoredStore.refreshConfiguration.idleRefreshInterval, 45 * 60)
        XCTAssertEqual(restoredStore.refreshConfiguration.activeRefreshInterval, 35)
    }
}

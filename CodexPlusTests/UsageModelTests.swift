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
}

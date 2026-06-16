import AppKit
import SwiftUI
import XCTest

@MainActor
final class MenuBarContentViewSmokeTests: XCTestCase {
    func testMenuBarContentViewCanRenderInHostingView() {
        let view = MenuBarContentView(
            snapshot: .preview,
            status: .current,
            budgetState: UsageBudgetState(
                configuration: UsageBudgetConfiguration(isEnabled: true),
                usedTokens: UsageSnapshot.preview.todayTotalTokens
            ),
            providerName: "Codex 桌面端（Mock）",
            lastErrorMessage: nil,
            menuBarDisplayMode: .constant(.currentSessionTokens),
            dataSourceMode: .constant(.codexDesktop),
            isDailyBudgetEnabled: .constant(true),
            dailyBudgetTokens: .constant(150_000),
            warningThresholdPercent: .constant(80),
            budgetNotificationsEnabled: .constant(false),
            onRefresh: {},
            onQuit: {}
        )
        let hostingView = NSHostingView(rootView: view.frame(width: 320))
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 720)

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
    }
}

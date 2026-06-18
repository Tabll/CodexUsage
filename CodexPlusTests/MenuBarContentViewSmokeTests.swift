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
            onRefresh: {},
            onQuit: {}
        )
        let hostingView = NSHostingView(rootView: view.frame(width: 300))
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 360)

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
    }

    func testSettingsViewCanRenderInHostingView() {
        let defaults = UserDefaults(suiteName: "CodexPlusTests.SettingsView") ?? .standard
        defaults.removePersistentDomain(forName: "CodexPlusTests.SettingsView")

        let view = SettingsView(
            settingsStore: SettingsStore(defaults: defaults),
            onBudgetConfigurationChange: { _ in },
            onDataSourceModeChange: { _ in },
            onRefreshConfigurationChange: { _ in }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 693)

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
        XCTAssertLessThanOrEqual(hostingView.fittingSize.height, 693)
    }
}

import AppKit
import SwiftUI

@main
@MainActor
struct CodexPlusApp: App {
    @StateObject private var usageService: UsageService
    @StateObject private var settingsStore: SettingsStore

    init() {
        let settingsStore = SettingsStore()

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _usageService = StateObject(
            wrappedValue: UsageService(
                provider: Self.makeUsageProvider(for: settingsStore.dataSourceMode),
                budgetConfiguration: settingsStore.budgetConfiguration,
                cachedSnapshot: settingsStore.cachedUsageSnapshot(for: settingsStore.dataSourceMode),
                refreshConfiguration: settingsStore.refreshConfiguration,
                onSnapshotUpdate: { snapshot in
                    settingsStore.saveCachedUsageSnapshot(snapshot, for: settingsStore.dataSourceMode)
                }
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                snapshot: usageService.snapshot,
                status: usageService.status,
                budgetState: usageService.budgetState,
                providerName: usageService.providerName,
                lastErrorMessage: usageService.lastErrorMessage,
                onRefresh: {
                    usageService.refresh()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .frame(width: 300)
        } label: {
            Text(
                settingsStore.menuBarDisplayMode.menuBarTitle(
                    for: usageService.snapshot,
                    status: usageService.status
                )
            )
        }
        .menuBarExtraStyle(.window)

        Window("设置", id: "settings") {
            SettingsView(
                settingsStore: settingsStore,
                onBudgetConfigurationChange: { configuration in
                    usageService.updateBudgetConfiguration(configuration)
                },
                onDataSourceModeChange: { dataSourceMode in
                    usageService.updateProvider(
                        Self.makeUsageProvider(for: dataSourceMode),
                        cachedSnapshot: settingsStore.cachedUsageSnapshot(for: dataSourceMode)
                    )
                },
                onRefreshConfigurationChange: { configuration in
                    usageService.updateRefreshConfiguration(configuration)
                }
            )
        }
        .defaultSize(width: 560, height: 693)
    }

    private static func makeUsageProvider(for dataSourceMode: UsageDataSourceMode) -> UsageProvider {
        switch dataSourceMode {
        case .codexDesktop:
            return CodexDesktopUsageProvider()
        case .mock:
            return MockUsageProvider()
        }
    }
}

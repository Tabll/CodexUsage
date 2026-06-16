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
                menuBarDisplayMode: $settingsStore.menuBarDisplayMode,
                dataSourceMode: $settingsStore.dataSourceMode,
                isDailyBudgetEnabled: $settingsStore.isDailyBudgetEnabled,
                dailyBudgetTokens: $settingsStore.dailyBudgetTokens,
                warningThresholdPercent: $settingsStore.warningThresholdPercent,
                budgetNotificationsEnabled: $settingsStore.budgetNotificationsEnabled,
                onRefresh: {
                    usageService.refresh()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .frame(width: 320)
            .onReceive(settingsStore.budgetConfigurationPublisher) { configuration in
                usageService.updateBudgetConfiguration(configuration)
            }
            .onReceive(settingsStore.dataSourceModePublisher.dropFirst()) { dataSourceMode in
                usageService.updateProvider(
                    Self.makeUsageProvider(for: dataSourceMode),
                    cachedSnapshot: settingsStore.cachedUsageSnapshot(for: dataSourceMode)
                )
            }
        } label: {
            Label(
                settingsStore.menuBarDisplayMode.menuBarTitle(
                    for: usageService.snapshot,
                    status: usageService.status
                ),
                systemImage: menuBarSystemImage
            )
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSystemImage: String {
        if usageService.status == .current {
            return settingsStore.menuBarDisplayMode.systemImage
        }

        return usageService.status.menuBarSystemImage
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

import AppKit
import SwiftUI

@main
@MainActor
struct CodexPlusApp: App {
    @StateObject private var usageService = UsageService(provider: CodexDesktopUsageProvider())
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                snapshot: usageService.snapshot,
                status: usageService.status,
                providerName: usageService.providerName,
                lastErrorMessage: usageService.lastErrorMessage,
                menuBarDisplayMode: $settingsStore.menuBarDisplayMode,
                onRefresh: {
                    usageService.refresh()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .frame(width: 320)
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
}

import AppKit
import SwiftUI

@main
@MainActor
struct CodexPlusApp: App {
    @StateObject private var usageService = UsageService(provider: MockUsageProvider())

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                snapshot: usageService.snapshot,
                status: usageService.status,
                providerName: usageService.providerName,
                lastErrorMessage: usageService.lastErrorMessage,
                onRefresh: {
                    usageService.refresh()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .frame(width: 320)
        } label: {
            Label(usageService.menuBarTitle, systemImage: usageService.status.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}

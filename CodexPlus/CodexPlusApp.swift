import AppKit
import SwiftUI

@main
struct CodexPlusApp: App {
    @State private var usage = PlaceholderUsage.sample

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                usage: usage,
                onRefresh: {
                    usage = usage.refreshed()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .frame(width: 320)
        } label: {
            Label(usage.menuBarTitle, systemImage: "bolt.horizontal.circle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}


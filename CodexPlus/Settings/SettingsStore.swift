import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedMode = defaults.string(forKey: Keys.menuBarDisplayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:))

        self.menuBarDisplayMode = savedMode ?? .currentSessionTokens
    }
}

private enum Keys {
    static let menuBarDisplayMode = "menuBarDisplayMode"
}


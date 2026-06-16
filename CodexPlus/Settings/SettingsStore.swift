import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode)
        }
    }

    @Published var isDailyBudgetEnabled: Bool {
        didSet {
            defaults.set(isDailyBudgetEnabled, forKey: Keys.isDailyBudgetEnabled)
        }
    }

    @Published var dailyBudgetTokens: Int {
        didSet {
            let clampedValue = UsageBudgetConfiguration.clampedDailyLimitTokens(dailyBudgetTokens)

            guard dailyBudgetTokens == clampedValue else {
                dailyBudgetTokens = clampedValue
                return
            }

            defaults.set(dailyBudgetTokens, forKey: Keys.dailyBudgetTokens)
        }
    }

    @Published var warningThresholdPercent: Int {
        didSet {
            let clampedValue = UsageBudgetConfiguration.clampedWarningThresholdPercent(warningThresholdPercent)

            guard warningThresholdPercent == clampedValue else {
                warningThresholdPercent = clampedValue
                return
            }

            defaults.set(warningThresholdPercent, forKey: Keys.warningThresholdPercent)
        }
    }

    @Published var budgetNotificationsEnabled: Bool {
        didSet {
            defaults.set(budgetNotificationsEnabled, forKey: Keys.budgetNotificationsEnabled)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedMode = defaults.string(forKey: Keys.menuBarDisplayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:))

        self.menuBarDisplayMode = savedMode ?? .currentSessionTokens
        self.isDailyBudgetEnabled = defaults.bool(forKey: Keys.isDailyBudgetEnabled)

        let savedDailyBudget = defaults.object(forKey: Keys.dailyBudgetTokens) == nil
            ? nil
            : defaults.integer(forKey: Keys.dailyBudgetTokens)
        self.dailyBudgetTokens = UsageBudgetConfiguration.clampedDailyLimitTokens(
            savedDailyBudget ?? UsageBudgetConfiguration.defaultDailyLimitTokens
        )

        let savedWarningThreshold = defaults.object(forKey: Keys.warningThresholdPercent) == nil
            ? nil
            : defaults.integer(forKey: Keys.warningThresholdPercent)
        self.warningThresholdPercent = UsageBudgetConfiguration.clampedWarningThresholdPercent(
            savedWarningThreshold ?? UsageBudgetConfiguration.defaultWarningThresholdPercent
        )

        self.budgetNotificationsEnabled = defaults.bool(forKey: Keys.budgetNotificationsEnabled)
    }

    var budgetConfiguration: UsageBudgetConfiguration {
        UsageBudgetConfiguration(
            isEnabled: isDailyBudgetEnabled,
            dailyLimitTokens: dailyBudgetTokens,
            warningThresholdPercent: warningThresholdPercent,
            notificationsEnabled: budgetNotificationsEnabled
        )
    }

    var budgetConfigurationPublisher: AnyPublisher<UsageBudgetConfiguration, Never> {
        Publishers.CombineLatest4(
            $isDailyBudgetEnabled,
            $dailyBudgetTokens,
            $warningThresholdPercent,
            $budgetNotificationsEnabled
        )
        .map { isEnabled, dailyLimitTokens, warningThresholdPercent, notificationsEnabled in
            UsageBudgetConfiguration(
                isEnabled: isEnabled,
                dailyLimitTokens: dailyLimitTokens,
                warningThresholdPercent: warningThresholdPercent,
                notificationsEnabled: notificationsEnabled
            )
        }
        .eraseToAnyPublisher()
    }
}

private enum Keys {
    static let menuBarDisplayMode = "menuBarDisplayMode"
    static let isDailyBudgetEnabled = "isDailyBudgetEnabled"
    static let dailyBudgetTokens = "dailyBudgetTokens"
    static let warningThresholdPercent = "warningThresholdPercent"
    static let budgetNotificationsEnabled = "budgetNotificationsEnabled"
}

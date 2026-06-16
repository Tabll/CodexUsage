import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode)
        }
    }

    @Published var dataSourceMode: UsageDataSourceMode {
        didSet {
            defaults.set(dataSourceMode.rawValue, forKey: Keys.dataSourceMode)
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
        let savedDataSourceMode = defaults.string(forKey: Keys.dataSourceMode)
            .flatMap(UsageDataSourceMode.init(rawValue:))

        self.menuBarDisplayMode = savedMode ?? .currentSessionTokens
        self.dataSourceMode = savedDataSourceMode ?? .codexDesktop
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

    var dataSourceModePublisher: AnyPublisher<UsageDataSourceMode, Never> {
        $dataSourceMode
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func cachedUsageSnapshot(for dataSourceMode: UsageDataSourceMode) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Keys.cachedUsageSnapshot),
              let envelope = try? Self.decoder.decode(CachedUsageSnapshotEnvelope.self, from: data),
              envelope.dataSourceMode == dataSourceMode else {
            return nil
        }

        return envelope.snapshot
    }

    func saveCachedUsageSnapshot(_ snapshot: UsageSnapshot, for dataSourceMode: UsageDataSourceMode) {
        let envelope = CachedUsageSnapshotEnvelope(
            dataSourceMode: dataSourceMode,
            snapshot: snapshot
        )

        guard let data = try? Self.encoder.encode(envelope) else {
            return
        }

        defaults.set(data, forKey: Keys.cachedUsageSnapshot)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

private enum Keys {
    static let menuBarDisplayMode = "menuBarDisplayMode"
    static let dataSourceMode = "dataSourceMode"
    static let isDailyBudgetEnabled = "isDailyBudgetEnabled"
    static let dailyBudgetTokens = "dailyBudgetTokens"
    static let warningThresholdPercent = "warningThresholdPercent"
    static let budgetNotificationsEnabled = "budgetNotificationsEnabled"
    static let cachedUsageSnapshot = "cachedUsageSnapshot"
}

private struct CachedUsageSnapshotEnvelope: Codable {
    let dataSourceMode: UsageDataSourceMode
    let snapshot: UsageSnapshot
}

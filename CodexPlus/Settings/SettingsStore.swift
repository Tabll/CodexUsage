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

    @Published var isIdlePollingEnabled: Bool {
        didSet {
            defaults.set(isIdlePollingEnabled, forKey: Keys.isIdlePollingEnabled)
        }
    }

    @Published var idleRefreshIntervalMinutes: Int {
        didSet {
            let clampedValue = UsageServiceRefreshDefaults.clampedIdleRefreshIntervalMinutes(
                idleRefreshIntervalMinutes
            )

            guard idleRefreshIntervalMinutes == clampedValue else {
                idleRefreshIntervalMinutes = clampedValue
                return
            }

            defaults.set(idleRefreshIntervalMinutes, forKey: Keys.idleRefreshIntervalMinutes)
        }
    }

    @Published var activeRefreshIntervalSeconds: Int {
        didSet {
            let clampedValue = UsageServiceRefreshDefaults.clampedActiveRefreshIntervalSeconds(
                activeRefreshIntervalSeconds
            )

            guard activeRefreshIntervalSeconds == clampedValue else {
                activeRefreshIntervalSeconds = clampedValue
                return
            }

            defaults.set(activeRefreshIntervalSeconds, forKey: Keys.activeRefreshIntervalSeconds)
        }
    }

    private let defaults: UserDefaults
    private let usageCache: SharedUsageCache

    init(
        defaults: UserDefaults = .standard,
        usageCache: SharedUsageCache = SharedUsageCache()
    ) {
        self.defaults = defaults
        self.usageCache = usageCache
        usageCache.migrateLegacySnapshotIfNeeded(from: defaults)

        let savedModeValue = defaults.string(forKey: Keys.menuBarDisplayMode)
        let savedMode = savedModeValue
            .flatMap(MenuBarDisplayMode.init(rawValue:))
        let savedDataSourceMode = defaults.string(forKey: Keys.dataSourceMode)
            .flatMap(UsageDataSourceMode.init(rawValue:))

        let didMigrateDefaultDisplayMode = defaults.bool(forKey: Keys.didMigrateDefaultDisplayMode)
        if !didMigrateDefaultDisplayMode, savedModeValue == nil || savedMode == .currentSessionTokens {
            self.menuBarDisplayMode = .rateLimitSummary
            defaults.set(MenuBarDisplayMode.rateLimitSummary.rawValue, forKey: Keys.menuBarDisplayMode)
            defaults.set(true, forKey: Keys.didMigrateDefaultDisplayMode)
        } else {
            self.menuBarDisplayMode = savedMode ?? .rateLimitSummary
        }

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
        self.isIdlePollingEnabled = defaults.object(forKey: Keys.isIdlePollingEnabled) == nil
            ? UsageServiceRefreshDefaults.isIdlePollingEnabled
            : defaults.bool(forKey: Keys.isIdlePollingEnabled)

        let savedIdleRefreshIntervalMinutes = defaults.object(forKey: Keys.idleRefreshIntervalMinutes) == nil
            ? nil
            : defaults.integer(forKey: Keys.idleRefreshIntervalMinutes)
        self.idleRefreshIntervalMinutes = UsageServiceRefreshDefaults.clampedIdleRefreshIntervalMinutes(
            savedIdleRefreshIntervalMinutes ?? Int(UsageServiceRefreshDefaults.idleRefreshInterval / 60)
        )

        let savedActiveRefreshIntervalSeconds = defaults.object(forKey: Keys.activeRefreshIntervalSeconds) == nil
            ? nil
            : defaults.integer(forKey: Keys.activeRefreshIntervalSeconds)
        self.activeRefreshIntervalSeconds = UsageServiceRefreshDefaults.clampedActiveRefreshIntervalSeconds(
            savedActiveRefreshIntervalSeconds ?? Int(UsageServiceRefreshDefaults.activeRefreshInterval)
        )
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

    var refreshConfiguration: UsageRefreshConfiguration {
        UsageRefreshConfiguration(
            isIdlePollingEnabled: isIdlePollingEnabled,
            idleRefreshInterval: TimeInterval(idleRefreshIntervalMinutes * 60),
            activeRefreshInterval: TimeInterval(activeRefreshIntervalSeconds)
        )
    }

    var dataSourceModePublisher: AnyPublisher<UsageDataSourceMode, Never> {
        $dataSourceMode
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func cachedUsageSnapshot(for dataSourceMode: UsageDataSourceMode) -> UsageSnapshot? {
        usageCache.cachedSnapshot(forDataSourceModeRawValue: dataSourceMode.rawValue)
    }

    func saveCachedUsageSnapshot(_ snapshot: UsageSnapshot, for dataSourceMode: UsageDataSourceMode) {
        usageCache.saveCachedSnapshot(
            snapshot,
            dataSourceModeRawValue: dataSourceMode.rawValue
        )
    }
}

private enum Keys {
    static let menuBarDisplayMode = "menuBarDisplayMode"
    static let dataSourceMode = "dataSourceMode"
    static let isDailyBudgetEnabled = "isDailyBudgetEnabled"
    static let dailyBudgetTokens = "dailyBudgetTokens"
    static let warningThresholdPercent = "warningThresholdPercent"
    static let budgetNotificationsEnabled = "budgetNotificationsEnabled"
    static let isIdlePollingEnabled = "isIdlePollingEnabled"
    static let idleRefreshIntervalMinutes = "idleRefreshIntervalMinutes"
    static let activeRefreshIntervalSeconds = "activeRefreshIntervalSeconds"
    static let didMigrateDefaultDisplayMode = "didMigrateDefaultDisplayMode"
}

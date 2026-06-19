import Foundation

enum SharedUsageCacheDefaults {
    static let appGroupIdentifier = "group.com.weitianshu.CodexPlus"
    static let widgetKind = "CodexUsageWidget"
}

struct SharedUsageCache {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedUsageCache.makeDefaultStore()) {
        self.defaults = defaults
    }

    func cachedSnapshot(forDataSourceModeRawValue dataSourceModeRawValue: String? = nil) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Keys.cachedUsageSnapshot),
              let envelope = try? Self.decoder.decode(CachedUsageSnapshotEnvelope.self, from: data) else {
            return nil
        }

        if let dataSourceModeRawValue, envelope.dataSourceModeRawValue != dataSourceModeRawValue {
            return nil
        }

        return envelope.snapshot
    }

    func saveCachedSnapshot(_ snapshot: UsageSnapshot, dataSourceModeRawValue: String) {
        let envelope = CachedUsageSnapshotEnvelope(
            dataSourceModeRawValue: dataSourceModeRawValue,
            snapshot: snapshot
        )

        guard let data = try? Self.encoder.encode(envelope) else {
            return
        }

        defaults.set(data, forKey: Keys.cachedUsageSnapshot)
    }

    func migrateLegacySnapshotIfNeeded(from legacyDefaults: UserDefaults = .standard) {
        Self.migrateLegacySnapshotIfNeeded(from: legacyDefaults, to: defaults)
    }

    static func migrateLegacySnapshotIfNeeded(
        from legacyDefaults: UserDefaults = .standard,
        to sharedDefaults: UserDefaults = makeDefaultStore()
    ) {
        guard !sharedDefaults.bool(forKey: Keys.didMigrateLegacySnapshot) else {
            return
        }

        if sharedDefaults.data(forKey: Keys.cachedUsageSnapshot) == nil,
           let legacyData = legacyDefaults.data(forKey: Keys.cachedUsageSnapshot) {
            sharedDefaults.set(legacyData, forKey: Keys.cachedUsageSnapshot)
        }

        sharedDefaults.set(true, forKey: Keys.didMigrateLegacySnapshot)
    }

    static func makeDefaultStore() -> UserDefaults {
        UserDefaults(suiteName: SharedUsageCacheDefaults.appGroupIdentifier) ?? .standard
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

private enum Keys {
    static let cachedUsageSnapshot = "cachedUsageSnapshot"
    static let didMigrateLegacySnapshot = "didMigrateCachedUsageSnapshotToAppGroup"
}

private struct CachedUsageSnapshotEnvelope: Codable {
    let dataSourceModeRawValue: String
    let snapshot: UsageSnapshot
}

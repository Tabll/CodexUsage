import Combine
import Darwin
import Dispatch
import Foundation
import UserNotifications

enum UsageServiceStatus: Equatable {
    case idle
    case refreshing
    case current
    case stale
    case warning(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "启动中"
        case .refreshing:
            return "刷新中"
        case .current:
            return "正常"
        case .stale:
            return "数据过期"
        case .warning(let message):
            return message
        case .failed:
            return "错误"
        }
    }

    var menuBarSystemImage: String {
        switch self {
        case .idle, .refreshing:
            return "arrow.clockwise.circle"
        case .current:
            return "bolt.horizontal.circle.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .warning:
            return "exclamationmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var status: UsageServiceStatus = .idle
    @Published private(set) var budgetState: UsageBudgetState
    @Published private(set) var lastErrorMessage: String?

    private var provider: UsageProvider
    private let refreshInterval: TimeInterval
    private let staleInterval: TimeInterval
    private let calendar: Calendar
    private let notificationCenter: UNUserNotificationCenter?
    private let onSnapshotUpdate: (UsageSnapshot) -> Void
    private var budgetConfiguration: UsageBudgetConfiguration
    private var budgetNotificationDay: Date?
    private var lastNotifiedBudgetSeverity: UsageBudgetSeverity = .normal
    private var pollingTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var fileWatchers: [FileChangeWatcher] = []

    init(
        provider: UsageProvider,
        budgetConfiguration: UsageBudgetConfiguration = .disabled,
        cachedSnapshot: UsageSnapshot? = nil,
        refreshInterval: TimeInterval = 8,
        staleInterval: TimeInterval = 30,
        calendar: Calendar = .current,
        notificationCenter: UNUserNotificationCenter? = nil,
        onSnapshotUpdate: @escaping (UsageSnapshot) -> Void = { _ in },
        startsImmediately: Bool = true
    ) {
        self.provider = provider
        self.budgetConfiguration = budgetConfiguration
        self.refreshInterval = refreshInterval
        self.staleInterval = staleInterval
        self.calendar = calendar
        self.notificationCenter = notificationCenter
        self.onSnapshotUpdate = onSnapshotUpdate

        let restoredSnapshot: UsageSnapshot?

        if let cachedSnapshot {
            let limitTokens = budgetConfiguration.isEnabled ? budgetConfiguration.dailyLimitTokens : nil
            restoredSnapshot = cachedSnapshot.withBudgetLimitTokens(limitTokens)
        } else {
            restoredSnapshot = nil
        }

        self.snapshot = restoredSnapshot
        self.status = restoredSnapshot == nil ? .idle : .stale
        self.budgetState = UsageBudgetState(
            configuration: budgetConfiguration,
            usedTokens: restoredSnapshot?.todayTotalTokens ?? 0
        )

        if startsImmediately {
            start()
        }
    }

    deinit {
        pollingTask?.cancel()
        staleTask?.cancel()
        fileWatchers.removeAll()
    }

    var menuBarTitle: String {
        if let snapshot {
            return UsageFormatting.tokens(snapshot.totalTokens)
        }

        if case .failed = status {
            return "错误"
        }

        return "CodexPlus"
    }

    var providerName: String {
        snapshot?.providerName ?? provider.name
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        startFileWatchers()

        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        staleTask?.cancel()
        staleTask = nil
        fileWatchers.removeAll()
    }

    func refresh() {
        Task { [weak self] in
            await self?.refreshNow()
        }
    }

    func updateBudgetConfiguration(_ configuration: UsageBudgetConfiguration) {
        budgetConfiguration = configuration

        guard let snapshot else {
            budgetState = UsageBudgetState(configuration: configuration, usedTokens: 0)
            return
        }

        let configuredSnapshot = applyBudgetConfiguration(to: snapshot)
        let nextBudgetState = UsageBudgetState(
            configuration: configuration,
            usedTokens: configuredSnapshot.todayTotalTokens
        )

        self.snapshot = configuredSnapshot
        budgetState = nextBudgetState
        resetBudgetNotificationStateIfNeeded(referenceDate: Date())

        if shouldStatusFollowBudget {
            status = status(for: nextBudgetState)
        }

        sendBudgetNotificationIfNeeded(for: nextBudgetState)
    }

    func updateProvider(_ provider: UsageProvider, cachedSnapshot: UsageSnapshot?) {
        self.provider = provider

        let restoredSnapshot: UsageSnapshot?

        if let cachedSnapshot {
            restoredSnapshot = applyBudgetConfiguration(to: cachedSnapshot)
        } else {
            restoredSnapshot = nil
        }

        snapshot = restoredSnapshot
        budgetState = UsageBudgetState(
            configuration: budgetConfiguration,
            usedTokens: restoredSnapshot?.todayTotalTokens ?? 0
        )
        lastErrorMessage = nil
        status = restoredSnapshot == nil ? .idle : .stale

        staleTask?.cancel()
        staleTask = nil
        fileWatchers.removeAll()
        startFileWatchers()
        refresh()
    }

    func refreshNow() async {
        status = .refreshing

        do {
            let nextSnapshot = try await provider.fetchSnapshot()
            let configuredSnapshot = applyBudgetConfiguration(to: nextSnapshot)
            let nextBudgetState = UsageBudgetState(
                configuration: budgetConfiguration,
                usedTokens: configuredSnapshot.todayTotalTokens
            )

            snapshot = configuredSnapshot
            budgetState = nextBudgetState
            lastErrorMessage = nil
            status = status(for: nextBudgetState)
            scheduleStaleCheck(from: configuredSnapshot.updatedAt)
            resetBudgetNotificationStateIfNeeded(referenceDate: Date())
            onSnapshotUpdate(configuredSnapshot)
            sendBudgetNotificationIfNeeded(for: nextBudgetState)
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            status = .failed(message)
        }
    }

    private func runPollingLoop() async {
        await refreshNow()

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: refreshInterval.nanoseconds)
            } catch {
                break
            }

            await refreshNow()
        }
    }

    private func scheduleStaleCheck(from updatedAt: Date) {
        staleTask?.cancel()
        let staleInterval = staleInterval

        staleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: staleInterval.nanoseconds)
            } catch {
                return
            }

            self?.markStaleIfNeeded(updatedAt: updatedAt)
        }
    }

    private func markStaleIfNeeded(updatedAt: Date) {
        guard shouldMarkStale, snapshot?.updatedAt == updatedAt else {
            return
        }

        if Date().timeIntervalSince(updatedAt) >= staleInterval {
            status = .stale
        }
    }

    private var shouldMarkStale: Bool {
        switch status {
        case .current, .warning:
            return true
        case .idle, .refreshing, .stale, .failed:
            return false
        }
    }

    private var shouldStatusFollowBudget: Bool {
        switch status {
        case .current, .warning:
            return true
        case .idle, .refreshing, .stale, .failed:
            return false
        }
    }

    private func applyBudgetConfiguration(to snapshot: UsageSnapshot) -> UsageSnapshot {
        let limitTokens = budgetConfiguration.isEnabled ? budgetConfiguration.dailyLimitTokens : nil
        return snapshot.withBudgetLimitTokens(limitTokens)
    }

    private func status(for budgetState: UsageBudgetState) -> UsageServiceStatus {
        switch budgetState.severity {
        case .disabled, .normal:
            return .current
        case .warning:
            return .warning("预算警告")
        case .exceeded:
            return .warning("预算超限")
        }
    }

    private func resetBudgetNotificationStateIfNeeded(referenceDate: Date) {
        let currentDay = calendar.startOfDay(for: referenceDate)

        guard budgetNotificationDay != currentDay else {
            return
        }

        budgetNotificationDay = currentDay
        lastNotifiedBudgetSeverity = .normal
    }

    private func sendBudgetNotificationIfNeeded(for budgetState: UsageBudgetState) {
        guard budgetState.configuration.isEnabled,
              budgetState.configuration.notificationsEnabled,
              budgetState.severity.isNotifiable,
              budgetState.severity.rawValue > lastNotifiedBudgetSeverity.rawValue else {
            return
        }

        lastNotifiedBudgetSeverity = budgetState.severity
        let notificationCenter = notificationCenter ?? .current()

        Task { [notificationCenter] in
            let isAuthorized = await Self.ensureNotificationAuthorization(using: notificationCenter)

            guard isAuthorized else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = budgetState.severity == .exceeded ? "CodexPlus 预算超限" : "CodexPlus 预算提醒"
            content.body = Self.notificationBody(for: budgetState)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "codexplus-budget-\(budgetState.severity.rawValue)-\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            )

            await Self.addNotification(request, using: notificationCenter)
        }
    }

    private static func notificationBody(for budgetState: UsageBudgetState) -> String {
        let usedText = UsageFormatting.tokens(budgetState.usedTokens)
        let limitText = UsageFormatting.tokens(
            budgetState.dailyLimitTokens ?? UsageBudgetConfiguration.defaultDailyLimitTokens
        )
        let percentText = budgetState.usedPercent.map { "\($0)%" } ?? "--"

        switch budgetState.severity {
        case .exceeded:
            return "今日已使用 \(usedText) / \(limitText) tokens，已超过每日预算。"
        case .warning:
            return "今日已使用 \(usedText) / \(limitText) tokens，已达到 \(percentText)。"
        case .disabled, .normal:
            return "今日用量仍在预算范围内。"
        }
    }

    private static func ensureNotificationAuthorization(
        using notificationCenter: UNUserNotificationCenter
    ) async -> Bool {
        let settings = await notificationSettings(using: notificationCenter)

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestNotificationAuthorization(using: notificationCenter)
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func notificationSettings(
        using notificationCenter: UNUserNotificationCenter
    ) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static func requestNotificationAuthorization(
        using notificationCenter: UNUserNotificationCenter
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { isGranted, _ in
                continuation.resume(returning: isGranted)
            }
        }
    }

    private static func addNotification(
        _ request: UNNotificationRequest,
        using notificationCenter: UNUserNotificationCenter
    ) async {
        await withCheckedContinuation { continuation in
            notificationCenter.add(request) { _ in
                continuation.resume()
            }
        }
    }

    private func startFileWatchers() {
        fileWatchers = provider.refreshHintFiles.compactMap { url in
            FileChangeWatcher(url: url) { [weak self] in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
    }
}

private extension TimeInterval {
    var nanoseconds: UInt64 {
        UInt64(self * 1_000_000_000)
    }
}

private final class FileChangeWatcher {
    private let fileDescriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)

        guard descriptor >= 0 else {
            return nil
        }

        fileDescriptor = descriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: .main
        )

        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

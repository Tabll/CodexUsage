import Combine
import Foundation

enum UsageServiceStatus: Equatable {
    case idle
    case refreshing
    case current
    case stale
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
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var status: UsageServiceStatus = .idle
    @Published private(set) var lastErrorMessage: String?

    private let provider: UsageProvider
    private let refreshInterval: TimeInterval
    private let staleInterval: TimeInterval
    private var pollingTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?

    init(
        provider: UsageProvider,
        refreshInterval: TimeInterval = 8,
        staleInterval: TimeInterval = 30,
        startsImmediately: Bool = true
    ) {
        self.provider = provider
        self.refreshInterval = refreshInterval
        self.staleInterval = staleInterval

        if startsImmediately {
            start()
        }
    }

    deinit {
        pollingTask?.cancel()
        staleTask?.cancel()
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

        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        staleTask?.cancel()
        staleTask = nil
    }

    func refresh() {
        Task { [weak self] in
            await self?.refreshNow()
        }
    }

    func refreshNow() async {
        status = .refreshing

        do {
            let nextSnapshot = try await provider.fetchSnapshot()
            snapshot = nextSnapshot
            lastErrorMessage = nil
            status = .current
            scheduleStaleCheck(from: nextSnapshot.updatedAt)
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
        staleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: staleInterval.nanoseconds)
            } catch {
                return
            }

            await self?.markStaleIfNeeded(updatedAt: updatedAt)
        }
    }

    private func markStaleIfNeeded(updatedAt: Date) {
        guard status == .current, snapshot?.updatedAt == updatedAt else {
            return
        }

        if Date().timeIntervalSince(updatedAt) >= staleInterval {
            status = .stale
        }
    }
}

private extension TimeInterval {
    var nanoseconds: UInt64 {
        UInt64(self * 1_000_000_000)
    }
}

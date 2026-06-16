import Foundation

actor MockUsageProvider: UsageProvider {
    nonisolated let name = "Codex 桌面端（Mock）"

    private let sessionId: String
    private let budgetLimitTokens: Int
    private let calendar: Calendar
    private var inputTokens: Int
    private var outputTokens: Int
    private var cachedInputTokens: Int
    private var reasoningTokens: Int
    private var todayTotalTokens: Int
    private var usageDay: Date

    init(
        sessionId: String = "mock-codex-desktop-session",
        inputTokens: Int = 7_200,
        outputTokens: Int = 3_100,
        cachedInputTokens: Int = 1_600,
        reasoningTokens: Int = 520,
        todayTotalTokens: Int = 58_940,
        budgetLimitTokens: Int = 150_000,
        calendar: Calendar = .current
    ) {
        self.sessionId = sessionId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningTokens = reasoningTokens
        self.todayTotalTokens = todayTotalTokens
        self.budgetLimitTokens = budgetLimitTokens
        self.calendar = calendar
        self.usageDay = calendar.startOfDay(for: Date())
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        let now = Date()
        let currentDay = calendar.startOfDay(for: now)

        if currentDay != usageDay {
            todayTotalTokens = 0
            usageDay = currentDay
        }

        let inputDelta = Int.random(in: 120...820)
        let outputDelta = Int.random(in: 80...520)
        let cachedDelta = Int.random(in: 0...180)
        let reasoningDelta = Int.random(in: 0...90)

        inputTokens += inputDelta
        outputTokens += outputDelta
        cachedInputTokens += cachedDelta
        reasoningTokens += reasoningDelta
        todayTotalTokens += inputDelta + outputDelta

        return UsageSnapshot(
            sessionId: sessionId,
            providerName: name,
            updatedAt: now,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedInputTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: inputTokens + outputTokens,
            todayTotalTokens: todayTotalTokens,
            estimatedCost: estimatedCost(),
            budgetLimitTokens: budgetLimitTokens,
            rateLimits: .preview
        )
    }

    private func estimatedCost() -> Decimal {
        let billableTokens = inputTokens + outputTokens + reasoningTokens
        return Decimal(billableTokens) / Decimal(1_000_000) * Decimal(3)
    }
}

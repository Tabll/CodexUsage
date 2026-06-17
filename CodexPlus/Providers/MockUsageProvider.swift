import Foundation

actor MockUsageProvider: UsageProvider, UsageHistoryProvider, UsageLatestMessageProvider {
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

    func fetchDailyUsageHistory(days: Int) async throws -> [DailyUsageSummary] {
        let dayCount = max(1, days)
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today

        return (0..<dayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
            let wave = Double(offset + 1) / Double(max(dayCount, 1))
            let weekdayBoost = calendar.component(.weekday, from: date).isMultiple(of: 3) ? 9_000 : 0
            let input = Int(22_000 + wave * 38_000) + weekdayBoost
            let output = Int(9_000 + wave * 16_000)
            let cached = Int(Double(input) * 0.28)
            let reasoning = Int(Double(output) * 0.18)

            return DailyUsageSummary(
                date: date,
                inputTokens: input,
                outputTokens: output,
                cachedInputTokens: cached,
                reasoningTokens: reasoning,
                totalTokens: input + output
            )
        }
    }

    func fetchLatestLogMessage() async throws -> CodexLogMessage {
        let now = Date()
        let timestampSeconds = Int64(now.timeIntervalSince1970)

        return CodexLogMessage(
            id: 42,
            timestamp: now,
            timestampSeconds: timestampSeconds,
            timestampNanoseconds: 120_000_000,
            level: "INFO",
            target: "codex_api::endpoint::responses_websocket",
            content: """
            session_loop{thread_id=mock-thread}:turn{turn.id=mock-turn}: websocket event: {"type":"response.completed","response":{"usage":{"input_tokens":7200,"output_tokens":3100,"total_tokens":10300,"input_tokens_details":{"cached_tokens":1600},"output_tokens_details":{"reasoning_tokens":520}}}}
            """,
            modulePath: "codex_api::endpoint",
            file: "responses_websocket.rs",
            line: 128,
            threadId: "mock-thread",
            processUUID: "mock-process-uuid",
            estimatedBytes: 418,
            databasePath: "Mock 数据"
        )
    }

    private func estimatedCost() -> Decimal {
        let billableTokens = inputTokens + outputTokens + reasoningTokens
        return Decimal(billableTokens) / Decimal(1_000_000) * Decimal(3)
    }
}

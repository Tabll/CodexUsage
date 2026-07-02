import Foundation
import SQLite3

struct CodexDesktopUsageProvider: UsageProvider, UsageHistoryProvider, UsageLatestMessageProvider {
    let name = "Codex 桌面端"

    private let databaseCandidates: [URL]
    private let calendar: Calendar
    private let recentRowLimit: Int

    init(
        databaseCandidates: [URL] = Self.defaultDatabaseCandidates(),
        calendar: Calendar = .current,
        recentRowLimit: Int = 2_000
    ) {
        self.databaseCandidates = databaseCandidates
        self.calendar = calendar
        self.recentRowLimit = recentRowLimit
    }

    var refreshHintFiles: [URL] {
        uniqueURLs(
            databaseCandidates.flatMap { databaseURL in
                [databaseURL.deletingLastPathComponent()] + refreshHintFiles(for: databaseURL)
            }
        )
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            try loadSnapshot()
        }.value
    }

    func fetchDailyUsageHistory(days: Int) async throws -> [DailyUsageSummary] {
        try await Task.detached(priority: .utility) {
            try loadDailyUsageHistory(days: days)
        }.value
    }

    func fetchLatestLogMessage() async throws -> CodexLogMessage {
        try await Task.detached(priority: .utility) {
            try loadLatestLogMessage()
        }.value
    }

    private func loadSnapshot() throws -> UsageSnapshot {
        let databaseURLs = readableDatabaseURLs()

        guard !databaseURLs.isEmpty else {
            throw UsageProviderError.unavailable("找不到 Codex 桌面端用量数据库")
        }

        var rows: [CodexUsageLogRow] = []
        var errors: [Error] = []

        for databaseURL in databaseURLs {
            do {
                rows.append(contentsOf: try readCandidateRows(from: databaseURL))
            } catch {
                errors.append(error)
            }
        }

        if !rows.isEmpty {
            return try makeSnapshot(from: rows)
        }

        if let providerError = errors.first as? UsageProviderError {
            throw providerError
        }

        throw UsageProviderError.unavailable("Codex 用量数据库中暂时没有可解析的 usage")
    }

    private func makeSnapshot(from rows: [CodexUsageLogRow]) throws -> UsageSnapshot {
        let events = readUsageEvents(from: rows)
        let latestRateLimits = readLatestRateLimits(from: rows)
        let latestEvent = events.max(by: { $0.timestamp < $1.timestamp })

        guard latestEvent != nil || latestRateLimits != nil else {
            throw UsageProviderError.unavailable("Codex 用量数据库中暂时没有可解析的 usage 或 rate limit")
        }

        let todayStart = calendar.startOfDay(for: Date())
        let currentSessionEvents = latestEvent.map { latestEvent in
            events.filter { $0.threadId == latestEvent.threadId }
        } ?? []
        let todayTotalTokens = events
            .filter { $0.timestamp >= todayStart }
            .reduce(0) { $0 + $1.totalTokens }
        let snapshotUpdatedAt = [latestEvent?.timestamp, latestRateLimits?.updatedAt]
            .compactMap { $0 }
            .max() ?? Date()

        return UsageSnapshot(
            sessionId: latestEvent?.threadId ?? "codex-desktop-rate-limits",
            providerName: name,
            updatedAt: snapshotUpdatedAt,
            inputTokens: currentSessionEvents.reduce(0) { $0 + $1.inputTokens },
            outputTokens: currentSessionEvents.reduce(0) { $0 + $1.outputTokens },
            cachedInputTokens: currentSessionEvents.reduce(0) { $0 + $1.cachedInputTokens },
            reasoningTokens: currentSessionEvents.reduce(0) { $0 + $1.reasoningTokens },
            totalTokens: currentSessionEvents.reduce(0) { $0 + $1.totalTokens },
            todayTotalTokens: todayTotalTokens,
            estimatedCost: nil,
            budgetLimitTokens: nil,
            rateLimits: latestRateLimits
        )
    }

    private func readUsageEvents(from rows: [CodexUsageLogRow]) -> [CodexUsageLogEvent] {
        var eventsByTurnId: [String: CodexUsageLogEvent] = [:]

        for row in rows {
            guard let event = CodexUsageLogParser.parseCompletedUsage(
                body: row.body,
                timestamp: row.timestamp
            ) else {
                continue
            }

            if let existingEvent = eventsByTurnId[event.turnId],
               !shouldReplaceUsageEvent(existingEvent, with: event) {
                continue
            }

            eventsByTurnId[event.turnId] = event
        }

        return Array(eventsByTurnId.values)
    }

    private func readLatestRateLimits(from rows: [CodexUsageLogRow]) -> UsageRateLimitSnapshot? {
        rows
            .compactMap { row in
                CodexUsageLogParser.parseRateLimits(
                    body: row.body,
                    timestamp: row.timestamp
                )
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func shouldReplaceUsageEvent(
        _ existingEvent: CodexUsageLogEvent,
        with candidateEvent: CodexUsageLogEvent
    ) -> Bool {
        if existingEvent.timestamp != candidateEvent.timestamp {
            return existingEvent.timestamp < candidateEvent.timestamp
        }

        return existingEvent.threadId == "codex-desktop" && candidateEvent.threadId != "codex-desktop"
    }

    private func loadDailyUsageHistory(days requestedDays: Int) throws -> [DailyUsageSummary] {
        let dayCount = max(1, requestedDays)
        let databaseURLs = readableDatabaseURLs()

        guard !databaseURLs.isEmpty else {
            throw UsageProviderError.unavailable("找不到 Codex 桌面端用量数据库")
        }

        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        let startTimestamp = Int64(startDay.timeIntervalSince1970)
        var eventsByTurnId: [String: CodexUsageLogEvent] = [:]
        var errors: [Error] = []
        var didReadDatabase = false

        for databaseURL in databaseURLs {
            do {
                let rows = try readHistoryRows(from: databaseURL, since: startTimestamp)
                didReadDatabase = true

                for row in rows {
                    guard let event = CodexUsageLogParser.parseCompletedUsage(
                        body: row.body,
                        timestamp: row.timestamp
                    ) else {
                        continue
                    }

                    if let existingEvent = eventsByTurnId[event.turnId],
                       !shouldReplaceUsageEvent(existingEvent, with: event) {
                        continue
                    }

                    eventsByTurnId[event.turnId] = event
                }
            } catch {
                errors.append(error)
            }
        }

        if !didReadDatabase, let providerError = errors.first as? UsageProviderError {
            throw providerError
        }

        return aggregateDailyUsage(
            Array(eventsByTurnId.values),
            startDay: startDay,
            dayCount: dayCount
        )
    }

    private func aggregateDailyUsage(
        _ events: [CodexUsageLogEvent],
        startDay: Date,
        dayCount: Int
    ) -> [DailyUsageSummary] {
        let endDay = calendar.date(byAdding: .day, value: dayCount, to: startDay) ?? startDay
        var summariesByDay: [Date: DailyUsageSummary] = [:]

        for offset in 0..<dayCount {
            let date = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
            summariesByDay[date] = DailyUsageSummary(date: date)
        }

        for event in events where event.timestamp >= startDay && event.timestamp < endDay {
            let day = calendar.startOfDay(for: event.timestamp)
            summariesByDay[day]?.add(
                inputTokens: event.inputTokens,
                outputTokens: event.outputTokens,
                cachedInputTokens: event.cachedInputTokens,
                reasoningTokens: event.reasoningTokens,
                totalTokens: event.totalTokens
            )
        }

        return (0..<dayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
            return summariesByDay[date] ?? DailyUsageSummary(date: date)
        }
    }

    private func loadLatestLogMessage() throws -> CodexLogMessage {
        let databaseURLs = readableDatabaseURLs()

        guard !databaseURLs.isEmpty else {
            throw UsageProviderError.unavailable("找不到 Codex 桌面端用量数据库")
        }

        var latestMessage: CodexLogMessage?
        var errors: [Error] = []

        for databaseURL in databaseURLs {
            do {
                let message = try readLatestLogMessage(from: databaseURL)

                if let currentLatest = latestMessage {
                    if isMessage(message, newerThan: currentLatest) {
                        latestMessage = message
                    }
                } else {
                    latestMessage = message
                }
            } catch {
                errors.append(error)
            }
        }

        if let latestMessage {
            return latestMessage
        }

        if let providerError = errors.first as? UsageProviderError {
            throw providerError
        }

        throw UsageProviderError.unavailable("Codex 用量数据库中暂时没有可读取的日志消息")
    }

    private func isMessage(_ lhs: CodexLogMessage, newerThan rhs: CodexLogMessage) -> Bool {
        if lhs.timestampSeconds != rhs.timestampSeconds {
            return lhs.timestampSeconds > rhs.timestampSeconds
        }

        if lhs.timestampNanoseconds != rhs.timestampNanoseconds {
            return lhs.timestampNanoseconds > rhs.timestampNanoseconds
        }

        return lhs.id > rhs.id
    }

    private func readCandidateRows(from databaseURL: URL) throws -> [CodexUsageLogRow] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let database {
                sqlite3_close(database)
            }
            throw UsageProviderError.unavailable(message)
        }

        defer {
            sqlite3_close(database)
        }

        sqlite3_busy_timeout(database, 100)

        let sql = """
        SELECT ts, feedback_log_body
        FROM logs
        WHERE target IN ('codex_api::endpoint::responses_websocket', 'log')
          AND (
            feedback_log_body LIKE '%"type":"response.completed"%'
            OR feedback_log_body LIKE '%"type":"codex.rate_limits"%'
          )
        ORDER BY ts DESC, id DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageProviderError.malformedData(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int(statement, 1, Int32(recentRowLimit))

        var rows: [CodexUsageLogRow] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0)))

            guard let bodyPointer = sqlite3_column_text(statement, 1) else {
                continue
            }

            rows.append(
                CodexUsageLogRow(
                    timestamp: timestamp,
                    body: String(cString: bodyPointer)
                )
            )
        }

        return rows
    }

    private func readLatestLogMessage(from databaseURL: URL) throws -> CodexLogMessage {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let database {
                sqlite3_close(database)
            }
            throw UsageProviderError.unavailable(message)
        }

        defer {
            sqlite3_close(database)
        }

        sqlite3_busy_timeout(database, 100)

        let sql = """
        SELECT
            id,
            ts,
            ts_nanos,
            level,
            target,
            feedback_log_body,
            module_path,
            file,
            line,
            thread_id,
            process_uuid,
            estimated_bytes
        FROM logs
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageProviderError.malformedData(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw UsageProviderError.unavailable("Codex 用量数据库中暂时没有日志消息")
        }

        let timestampSeconds = sqlite3_column_int64(statement, 1)
        let timestampNanoseconds = sqlite3_column_int64(statement, 2)
        let timestamp = Date(
            timeIntervalSince1970: TimeInterval(timestampSeconds) + TimeInterval(timestampNanoseconds) / 1_000_000_000
        )

        return CodexLogMessage(
            id: sqlite3_column_int64(statement, 0),
            timestamp: timestamp,
            timestampSeconds: timestampSeconds,
            timestampNanoseconds: timestampNanoseconds,
            level: columnText(statement, 3) ?? "",
            target: columnText(statement, 4) ?? "",
            content: columnText(statement, 5),
            modulePath: columnText(statement, 6),
            file: columnText(statement, 7),
            line: optionalInt(statement, 8),
            threadId: columnText(statement, 9),
            processUUID: columnText(statement, 10),
            estimatedBytes: sqlite3_column_int64(statement, 11),
            databasePath: databaseURL.path
        )
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: pointer)
    }

    private func optionalInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return Int(sqlite3_column_int(statement, index))
    }

    private func readHistoryRows(from databaseURL: URL, since startTimestamp: Int64) throws -> [CodexUsageLogRow] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let database {
                sqlite3_close(database)
            }
            throw UsageProviderError.unavailable(message)
        }

        defer {
            sqlite3_close(database)
        }

        sqlite3_busy_timeout(database, 100)

        let sql = """
        SELECT ts, feedback_log_body
        FROM logs
        WHERE target IN ('codex_api::endpoint::responses_websocket', 'log')
          AND ts >= ?
          AND feedback_log_body LIKE '%"type":"response.completed"%'
        ORDER BY ts ASC, id ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageProviderError.malformedData(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, startTimestamp)

        var rows: [CodexUsageLogRow] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0)))

            guard let bodyPointer = sqlite3_column_text(statement, 1) else {
                continue
            }

            rows.append(
                CodexUsageLogRow(
                    timestamp: timestamp,
                    body: String(cString: bodyPointer)
                )
            )
        }

        return rows
    }

    private func readableDatabaseURLs() -> [URL] {
        databaseCandidates.filter { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    private func refreshHintFiles(for databaseURL: URL) -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()

        return urls.filter { url in
            let path = url.standardizedFileURL.path
            return seenPaths.insert(path).inserted
        }
    }

    private static func defaultDatabaseCandidates() -> [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let codexDirectory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)

        return [
            codexDirectory.appendingPathComponent("logs_2.sqlite"),
            codexDirectory
                .appendingPathComponent("sqlite", isDirectory: true)
                .appendingPathComponent("logs_2.sqlite")
        ]
    }
}

private struct CodexUsageLogRow {
    let timestamp: Date
    let body: String
}

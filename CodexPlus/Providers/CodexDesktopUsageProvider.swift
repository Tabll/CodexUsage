import Foundation
import SQLite3

struct CodexDesktopUsageProvider: UsageProvider {
    let name = "Codex 桌面端"

    private let databaseCandidates: [URL]
    private let calendar: Calendar
    private let recentRowLimit: Int

    init(
        databaseCandidates: [URL] = Self.defaultDatabaseCandidates(),
        calendar: Calendar = .current,
        recentRowLimit: Int = 5_000
    ) {
        self.databaseCandidates = databaseCandidates
        self.calendar = calendar
        self.recentRowLimit = recentRowLimit
    }

    var refreshHintFiles: [URL] {
        guard let databaseURL = firstReadableDatabaseURL() else {
            return []
        }

        return [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            try loadSnapshot()
        }.value
    }

    private func loadSnapshot() throws -> UsageSnapshot {
        guard let databaseURL = firstReadableDatabaseURL() else {
            throw UsageProviderError.unavailable("找不到 Codex 桌面端用量数据库")
        }

        let events = try readUsageEvents(from: databaseURL)

        guard let latestEvent = events.max(by: { $0.timestamp < $1.timestamp }) else {
            throw UsageProviderError.unavailable("Codex 用量数据库中暂时没有可解析的 response.completed usage")
        }

        let todayStart = calendar.startOfDay(for: Date())
        let currentSessionEvents = events.filter { $0.threadId == latestEvent.threadId }
        let todayTotalTokens = events
            .filter { $0.timestamp >= todayStart }
            .reduce(0) { $0 + $1.totalTokens }

        return UsageSnapshot(
            sessionId: latestEvent.threadId,
            providerName: name,
            updatedAt: latestEvent.timestamp,
            inputTokens: currentSessionEvents.reduce(0) { $0 + $1.inputTokens },
            outputTokens: currentSessionEvents.reduce(0) { $0 + $1.outputTokens },
            cachedInputTokens: currentSessionEvents.reduce(0) { $0 + $1.cachedInputTokens },
            reasoningTokens: currentSessionEvents.reduce(0) { $0 + $1.reasoningTokens },
            totalTokens: currentSessionEvents.reduce(0) { $0 + $1.totalTokens },
            todayTotalTokens: todayTotalTokens,
            estimatedCost: nil,
            budgetLimitTokens: nil
        )
    }

    private func readUsageEvents(from databaseURL: URL) throws -> [CodexUsageLogEvent] {
        let rows = try readCandidateRows(from: databaseURL)
        var eventsByTurnId: [String: CodexUsageLogEvent] = [:]

        for row in rows {
            guard let event = CodexUsageLogParser.parseCompletedUsage(
                body: row.body,
                timestamp: row.timestamp
            ) else {
                continue
            }

            eventsByTurnId[event.turnId] = event
        }

        return Array(eventsByTurnId.values)
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

        let sql = """
        SELECT ts, feedback_log_body
        FROM logs
        WHERE target = 'codex_api::endpoint::responses_websocket'
          AND feedback_log_body LIKE '%"usage":%'
        ORDER BY id DESC
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

    private func firstReadableDatabaseURL() -> URL? {
        databaseCandidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    private static func defaultDatabaseCandidates() -> [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let codexDirectory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)

        return [
            codexDirectory
                .appendingPathComponent("sqlite", isDirectory: true)
                .appendingPathComponent("logs_2.sqlite"),
            codexDirectory.appendingPathComponent("logs_2.sqlite")
        ]
    }
}

private struct CodexUsageLogRow {
    let timestamp: Date
    let body: String
}

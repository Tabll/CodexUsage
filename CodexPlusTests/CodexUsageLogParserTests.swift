import SQLite3
import XCTest

final class CodexUsageLogParserTests: XCTestCase {
    func testParseCompletedUsageFromFixture() throws {
        let body = try fixture(named: "response_completed_usage", fileExtension: "log")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let event = try XCTUnwrap(
            CodexUsageLogParser.parseCompletedUsage(
                body: body,
                timestamp: timestamp
            )
        )

        XCTAssertEqual(event.timestamp, timestamp)
        XCTAssertEqual(event.threadId, "fixture-thread")
        XCTAssertEqual(event.turnId, "fixture-turn")
        XCTAssertEqual(event.inputTokens, 1_200)
        XCTAssertEqual(event.cachedInputTokens, 400)
        XCTAssertEqual(event.outputTokens, 300)
        XCTAssertEqual(event.reasoningTokens, 80)
        XCTAssertEqual(event.totalTokens, 1_500)
    }

    func testParseRateLimitsFromFixture() throws {
        let body = try fixture(named: "codex_rate_limits", fileExtension: "log")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)

        let snapshot = try XCTUnwrap(
            CodexUsageLogParser.parseRateLimits(
                body: body,
                timestamp: timestamp
            )
        )

        XCTAssertEqual(snapshot.planType, "prolite")
        XCTAssertEqual(snapshot.updatedAt, timestamp)
        XCTAssertTrue(snapshot.allowed)
        XCTAssertFalse(snapshot.limitReached)

        let shortWindow = try XCTUnwrap(snapshot.shortWindow)
        XCTAssertEqual(shortWindow.usedPercent, 41)
        XCTAssertEqual(shortWindow.remainingPercent, 59)
        XCTAssertEqual(shortWindow.windowMinutes, 300)
        XCTAssertEqual(shortWindow.resetAfterSeconds, 2_335)
        XCTAssertEqual(shortWindow.resetAt, Date(timeIntervalSince1970: 1_781_631_830))

        let weeklyWindow = try XCTUnwrap(snapshot.weeklyWindow)
        XCTAssertEqual(weeklyWindow.usedPercent, 56)
        XCTAssertEqual(weeklyWindow.remainingPercent, 44)
        XCTAssertEqual(weeklyWindow.windowMinutes, 10_080)
        XCTAssertEqual(weeklyWindow.resetAfterSeconds, 118_153)
        XCTAssertEqual(weeklyWindow.resetAt, Date(timeIntervalSince1970: 1_781_747_648))
    }

    func testParserIgnoresUnrelatedLogBody() {
        let body = "session_loop{thread_id=fixture}: websocket event: {\"type\":\"response.started\"}"
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(CodexUsageLogParser.parseCompletedUsage(body: body, timestamp: timestamp))
        XCTAssertNil(CodexUsageLogParser.parseRateLimits(body: body, timestamp: timestamp))
    }

    func testDesktopProviderChoosesLatestReadableDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPlusTests-\(UUID().uuidString)", isDirectory: true)
        let staleDatabaseURL = directory.appendingPathComponent("stale.sqlite")
        let freshDatabaseURL = directory.appendingPathComponent("fresh.sqlite")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try writeUsageDatabase(
            at: staleDatabaseURL,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            shortUsedPercent: 20,
            weeklyUsedPercent: 62
        )
        try writeUsageDatabase(
            at: freshDatabaseURL,
            timestamp: Date(timeIntervalSince1970: 1_700_000_200),
            shortUsedPercent: 19,
            weeklyUsedPercent: 72
        )

        let provider = CodexDesktopUsageProvider(
            databaseCandidates: [staleDatabaseURL, freshDatabaseURL],
            recentRowLimit: 20
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.updatedAt, Date(timeIntervalSince1970: 1_700_000_200))
        XCTAssertEqual(snapshot.rateLimits?.shortWindow?.remainingPercent, 81)
        XCTAssertEqual(snapshot.rateLimits?.weeklyWindow?.remainingPercent, 28)
    }

    func testDesktopProviderAggregatesDailyUsageHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPlusTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw sqliteError(database)
        }

        defer {
            sqlite3_close(database)
        }

        try createLogsTable(database: database)
        try insertLogBody(
            completedUsageBody(
                timestamp: yesterday.addingTimeInterval(3_600),
                inputTokens: 100,
                outputTokens: 20,
                cachedInputTokens: 12,
                reasoningTokens: 4,
                totalTokens: 120
            ),
            timestamp: yesterday.addingTimeInterval(3_600),
            database: database
        )
        try insertLogBody(
            completedUsageBody(
                timestamp: yesterday.addingTimeInterval(7_200),
                inputTokens: 50,
                outputTokens: 25,
                cachedInputTokens: 8,
                reasoningTokens: 5,
                totalTokens: 75
            ),
            timestamp: yesterday.addingTimeInterval(7_200),
            database: database
        )
        try insertLogBody(
            completedUsageBody(
                timestamp: today.addingTimeInterval(3_600),
                inputTokens: 200,
                outputTokens: 80,
                cachedInputTokens: 40,
                reasoningTokens: 16,
                totalTokens: 280
            ),
            timestamp: today.addingTimeInterval(3_600),
            database: database
        )

        let provider = CodexDesktopUsageProvider(
            databaseCandidates: [databaseURL],
            calendar: calendar,
            recentRowLimit: 20
        )

        let history = try await provider.fetchDailyUsageHistory(days: 3)

        XCTAssertEqual(history.map(\.date), [twoDaysAgo, yesterday, today])
        XCTAssertEqual(history[0].totalTokens, 0)
        XCTAssertEqual(history[1].inputTokens, 150)
        XCTAssertEqual(history[1].outputTokens, 45)
        XCTAssertEqual(history[1].cachedInputTokens, 20)
        XCTAssertEqual(history[1].reasoningTokens, 9)
        XCTAssertEqual(history[1].totalTokens, 195)
        XCTAssertEqual(history[2].totalTokens, 280)
    }

    private func fixture(named name: String, fileExtension: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: fileExtension)
        )

        return try String(contentsOf: url, encoding: .utf8)
    }

    private func writeUsageDatabase(
        at url: URL,
        timestamp: Date,
        shortUsedPercent: Int,
        weeklyUsedPercent: Int
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw sqliteError(database)
        }

        defer {
            sqlite3_close(database)
        }

        try createLogsTable(database: database)

        try insertLogBody(
            completedUsageBody(timestamp: timestamp),
            timestamp: timestamp,
            database: database
        )
        try insertLogBody(
            rateLimitsBody(
                timestamp: timestamp,
                shortUsedPercent: shortUsedPercent,
                weeklyUsedPercent: weeklyUsedPercent
            ),
            timestamp: timestamp,
            database: database
        )
    }

    private func createLogsTable(database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                target TEXT NOT NULL,
                feedback_log_body TEXT NOT NULL
            );
            """,
            database: database
        )
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(database)
        }
    }

    private func insertLogBody(_ body: String, timestamp: Date, database: OpaquePointer) throws {
        let escapedBody = body.replacingOccurrences(of: "'", with: "''")
        let timestampSeconds = Int(timestamp.timeIntervalSince1970)

        try execute(
            """
            INSERT INTO logs (ts, target, feedback_log_body)
            VALUES (
                \(timestampSeconds),
                'codex_api::endpoint::responses_websocket',
                '\(escapedBody)'
            );
            """,
            database: database
        )
    }

    private func completedUsageBody(timestamp: Date) -> String {
        completedUsageBody(
            timestamp: timestamp,
            inputTokens: 100,
            outputTokens: 20,
            cachedInputTokens: 0,
            reasoningTokens: 0,
            totalTokens: 120
        )
    }

    private func completedUsageBody(
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int
    ) -> String {
        let timestampSeconds = Int(timestamp.timeIntervalSince1970)

        return """
        session_loop{thread_id=fixture-thread}:turn{turn.id=fixture-turn-\(timestampSeconds)}: websocket event: {"type":"response.completed","response":{"usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"total_tokens":\(totalTokens),"input_tokens_details":{"cached_tokens":\(cachedInputTokens)},"output_tokens_details":{"reasoning_tokens":\(reasoningTokens)}}}}
        """
    }

    private func rateLimitsBody(
        timestamp: Date,
        shortUsedPercent: Int,
        weeklyUsedPercent: Int
    ) -> String {
        let timestampSeconds = Int(timestamp.timeIntervalSince1970)

        return """
        session_loop{thread_id=fixture-thread}:turn{turn.id=fixture-rate-limit-\(timestampSeconds)}: websocket event: {"type":"codex.rate_limits","plan_type":"prolite","rate_limits":{"allowed":true,"limit_reached":false,"primary":{"used_percent":\(shortUsedPercent),"window_minutes":300,"reset_after_seconds":4600,"reset_at":\(timestampSeconds + 4_600)},"secondary":{"used_percent":\(weeklyUsedPercent),"window_minutes":10080,"reset_after_seconds":45477,"reset_at":\(timestampSeconds + 45_477)}},"credits":null,"promo":null}
        """
    }

    private func sqliteError(_ database: OpaquePointer?) -> NSError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开 SQLite 数据库"

        return NSError(
            domain: "CodexPlusTests.SQLite",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

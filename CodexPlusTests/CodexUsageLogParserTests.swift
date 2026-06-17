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
        let timestampSeconds = Int(timestamp.timeIntervalSince1970)

        return """
        session_loop{thread_id=fixture-thread}:turn{turn.id=fixture-turn-\(timestampSeconds)}: websocket event: {"type":"response.completed","response":{"usage":{"input_tokens":100,"output_tokens":20,"total_tokens":120,"input_tokens_details":{"cached_tokens":0},"output_tokens_details":{"reasoning_tokens":0}}}}
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

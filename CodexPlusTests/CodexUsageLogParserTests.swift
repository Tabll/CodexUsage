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

    func testDesktopProviderReadsRateLimitsWithoutCompletedUsage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPlusTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("rate-limits-only.sqlite")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_300)

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
            rateLimitsBody(
                timestamp: timestamp,
                shortUsedPercent: 12,
                weeklyUsedPercent: 11
            ),
            timestamp: timestamp,
            database: database
        )

        let provider = CodexDesktopUsageProvider(
            databaseCandidates: [databaseURL],
            recentRowLimit: 20
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.sessionId, "codex-desktop-rate-limits")
        XCTAssertEqual(snapshot.updatedAt, timestamp)
        XCTAssertEqual(snapshot.inputTokens, 0)
        XCTAssertEqual(snapshot.outputTokens, 0)
        XCTAssertEqual(snapshot.cachedInputTokens, 0)
        XCTAssertEqual(snapshot.reasoningTokens, 0)
        XCTAssertEqual(snapshot.totalTokens, 0)
        XCTAssertEqual(snapshot.todayTotalTokens, 0)
        XCTAssertEqual(snapshot.rateLimits?.shortWindow?.remainingPercent, 88)
        XCTAssertEqual(snapshot.rateLimits?.weeklyWindow?.remainingPercent, 89)
    }

    func testDesktopProviderWatchesAllDatabaseCandidates() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPlusTests-\(UUID().uuidString)", isDirectory: true)
        let primaryDatabaseURL = directory.appendingPathComponent("logs_2.sqlite")
        let secondaryDatabaseURL = directory
            .appendingPathComponent("sqlite", isDirectory: true)
            .appendingPathComponent("logs_2.sqlite")
        let provider = CodexDesktopUsageProvider(
            databaseCandidates: [primaryDatabaseURL, secondaryDatabaseURL]
        )
        let hintPaths = Set(provider.refreshHintFiles.map(\.standardizedFileURL.path))

        XCTAssertTrue(hintPaths.contains(directory.standardizedFileURL.path))
        XCTAssertTrue(hintPaths.contains(primaryDatabaseURL.standardizedFileURL.path))
        XCTAssertTrue(hintPaths.contains(primaryDatabaseURL.standardizedFileURL.path + "-wal"))
        XCTAssertTrue(hintPaths.contains(primaryDatabaseURL.standardizedFileURL.path + "-shm"))
        XCTAssertTrue(hintPaths.contains(secondaryDatabaseURL.deletingLastPathComponent().standardizedFileURL.path))
        XCTAssertTrue(hintPaths.contains(secondaryDatabaseURL.standardizedFileURL.path))
        XCTAssertTrue(hintPaths.contains(secondaryDatabaseURL.standardizedFileURL.path + "-wal"))
        XCTAssertTrue(hintPaths.contains(secondaryDatabaseURL.standardizedFileURL.path + "-shm"))
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

    func testDesktopProviderReadsLatestLogMessage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPlusTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("latest-message.sqlite")
        let olderTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let newerTimestamp = Date(timeIntervalSince1970: 1_700_000_100)

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

        try createFullLogsTable(database: database)
        try insertFullLogMessage(
            timestamp: olderTimestamp,
            timestampNanoseconds: 1,
            level: "DEBUG",
            target: "older-target",
            body: "older body",
            threadId: "older-thread",
            database: database
        )
        try insertFullLogMessage(
            timestamp: newerTimestamp,
            timestampNanoseconds: 9,
            level: "INFO",
            target: "newer-target",
            body: "newer body",
            threadId: "newer-thread",
            database: database
        )

        let provider = CodexDesktopUsageProvider(databaseCandidates: [databaseURL])
        let message = try await provider.fetchLatestLogMessage()

        XCTAssertEqual(message.timestampSeconds, Int64(newerTimestamp.timeIntervalSince1970))
        XCTAssertEqual(message.timestampNanoseconds, 9)
        XCTAssertEqual(message.level, "INFO")
        XCTAssertEqual(message.target, "newer-target")
        XCTAssertEqual(message.content, "newer body")
        XCTAssertEqual(message.threadId, "newer-thread")
        XCTAssertEqual(message.modulePath, "test.module")
        XCTAssertEqual(message.file, "test.swift")
        XCTAssertEqual(message.line, 42)
        XCTAssertEqual(message.processUUID, "test-process")
        XCTAssertEqual(message.estimatedBytes, 128)
        XCTAssertEqual(message.databasePath, databaseURL.path)
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

    private func createFullLogsTable(database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                ts_nanos INTEGER NOT NULL,
                level TEXT NOT NULL,
                target TEXT NOT NULL,
                feedback_log_body TEXT,
                module_path TEXT,
                file TEXT,
                line INTEGER,
                thread_id TEXT,
                process_uuid TEXT,
                estimated_bytes INTEGER NOT NULL DEFAULT 0
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

    private func insertFullLogMessage(
        timestamp: Date,
        timestampNanoseconds: Int,
        level: String,
        target: String,
        body: String,
        threadId: String,
        database: OpaquePointer
    ) throws {
        let values = [
            level,
            target,
            body,
            "test.module",
            "test.swift",
            threadId,
            "test-process"
        ].map { $0.replacingOccurrences(of: "'", with: "''") }
        let timestampSeconds = Int(timestamp.timeIntervalSince1970)

        try execute(
            """
            INSERT INTO logs (
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
            )
            VALUES (
                \(timestampSeconds),
                \(timestampNanoseconds),
                '\(values[0])',
                '\(values[1])',
                '\(values[2])',
                '\(values[3])',
                '\(values[4])',
                42,
                '\(values[5])',
                '\(values[6])',
                128
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

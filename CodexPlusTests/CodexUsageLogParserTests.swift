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

    private func fixture(named name: String, fileExtension: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: fileExtension)
        )

        return try String(contentsOf: url, encoding: .utf8)
    }
}

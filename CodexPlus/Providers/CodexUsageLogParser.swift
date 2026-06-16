import Foundation

struct CodexUsageLogEvent: Equatable {
    let timestamp: Date
    let threadId: String
    let turnId: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
}

enum CodexUsageLogParser {
    static func parseCompletedUsage(body: String, timestamp: Date) -> CodexUsageLogEvent? {
        guard let eventData = extractEventJSON(from: body),
              let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
              event["type"] as? String == "response.completed",
              let response = event["response"] as? [String: Any],
              let usage = response["usage"] as? [String: Any] else {
            return nil
        }

        let inputTokens = intValue(usage["input_tokens"])
        let outputTokens = intValue(usage["output_tokens"])
        let totalTokens = intValue(usage["total_tokens"], fallback: inputTokens + outputTokens)
        let threadId = extractAttribute("thread_id", from: body)
            ?? extractAttribute("thread.id", from: body)
            ?? "codex-desktop"
        let turnId = extractAttribute("turn_id", from: body)
            ?? extractAttribute("turn.id", from: body)
            ?? "\(Int(timestamp.timeIntervalSince1970))-\(totalTokens)"

        let inputDetails = usage["input_tokens_details"] as? [String: Any]
        let outputDetails = usage["output_tokens_details"] as? [String: Any]

        return CodexUsageLogEvent(
            timestamp: timestamp,
            threadId: threadId,
            turnId: turnId,
            inputTokens: inputTokens,
            cachedInputTokens: intValue(inputDetails?["cached_tokens"]),
            outputTokens: outputTokens,
            reasoningTokens: intValue(outputDetails?["reasoning_tokens"]),
            totalTokens: totalTokens
        )
    }

    static func parseRateLimits(body: String, timestamp: Date) -> UsageRateLimitSnapshot? {
        guard let eventData = extractEventJSON(from: body),
              let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
              event["type"] as? String == "codex.rate_limits",
              let rateLimits = event["rate_limits"] as? [String: Any] else {
            return nil
        }

        let primary = parseRateLimitWindow(rateLimits["primary"])
        let secondary = parseRateLimitWindow(rateLimits["secondary"])
        let monthly = parseMonthlyWindow(in: rateLimits)
        let windows = [primary, secondary, monthly].compactMap { $0 }

        return UsageRateLimitSnapshot(
            planType: event["plan_type"] as? String,
            updatedAt: timestamp,
            allowed: boolValue(rateLimits["allowed"], fallback: windows.contains { $0.remainingPercent > 0 }),
            limitReached: boolValue(rateLimits["limit_reached"], fallback: false),
            shortWindow: windows.first { $0.windowMinutes == 300 },
            weeklyWindow: windows.first { $0.windowMinutes == 10_080 },
            monthlyWindow: windows.first { $0.windowMinutes >= 40_000 }
        )
    }

    private static func parseMonthlyWindow(in rateLimits: [String: Any]) -> UsageRateLimitWindow? {
        let candidateKeys = [
            "monthly",
            "monthly_credit",
            "monthly_credits",
            "credits",
            "workspace_credits"
        ]

        for key in candidateKeys {
            if let window = parseRateLimitWindow(rateLimits[key]) {
                return window
            }
        }

        return nil
    }

    private static func parseRateLimitWindow(_ value: Any?) -> UsageRateLimitWindow? {
        guard let value = value as? [String: Any] else {
            return nil
        }

        let usedPercent = intValue(value["used_percent"])
        let windowMinutes = intValue(value["window_minutes"])
        let resetAfterSeconds = optionalIntValue(value["reset_after_seconds"])
        let resetAt: Date?

        if let resetAtSeconds = optionalDoubleValue(value["reset_at"]) {
            resetAt = Date(timeIntervalSince1970: resetAtSeconds)
        } else {
            resetAt = nil
        }

        return UsageRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetAfterSeconds: resetAfterSeconds,
            resetAt: resetAt
        )
    }

    private static func intValue(_ value: Any?, fallback: Int = 0) -> Int {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return fallback
    }

    private static func optionalIntValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private static func optionalDoubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }

        if let value = value as? NSNumber {
            return value.doubleValue
        }

        return nil
    }

    private static func boolValue(_ value: Any?, fallback: Bool) -> Bool {
        if let value = value as? Bool {
            return value
        }

        if let value = value as? NSNumber {
            return value.boolValue
        }

        return fallback
    }

    private static func extractEventJSON(from body: String) -> Data? {
        let markers = [
            "websocket event: ",
            "Received message "
        ]

        for marker in markers {
            guard let markerRange = body.range(of: marker),
                  let openingBrace = body[markerRange.upperBound...].firstIndex(of: "{"),
                  let jsonRange = balancedJSONRange(startingAt: openingBrace, in: body) else {
                continue
            }

            return Data(body[jsonRange].utf8)
        }

        return nil
    }

    private static func balancedJSONRange(startingAt start: String.Index, in body: String) -> Range<String.Index>? {
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start

        while index < body.endIndex {
            let character = body[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1

                    if depth == 0 {
                        let end = body.index(after: index)
                        return start..<end
                    }
                }
            }

            index = body.index(after: index)
        }

        return nil
    }

    private static func extractAttribute(_ key: String, from body: String) -> String? {
        let token = "\(key)="
        guard let range = body.range(of: token) else {
            return nil
        }

        let start = range.upperBound
        let tail = body[start...]
        let end = tail.firstIndex { character in
            character == " " || character == "}" || character == ":" || character == ","
        } ?? body.endIndex

        let value = String(body[start..<end])
        return value.isEmpty ? nil : value
    }
}

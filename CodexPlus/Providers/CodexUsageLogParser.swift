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

    private static func intValue(_ value: Any?, fallback: Int = 0) -> Int {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
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

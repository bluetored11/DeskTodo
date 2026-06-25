import Foundation

// MARK: - Errors

enum OpenAIError: Error {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
}

// MARK: - Codable types

private struct OpenAIRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let stream: Bool
    let maxTokens: Int
    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case maxTokens = "max_tokens"
    }
}

struct OpenAIChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}

// MARK: - Service

final class OpenAIService: @unchecked Sendable {
    static let shared = OpenAIService()
    private init() {}

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private static let systemPrompt = """
        你是一个任务规划助手。将用户描述的任务拆解为 3-7 个具体可执行的步骤。
        输出格式（严格遵守）：
        - 第一行：任务标题（不超过 20 字，不含序号）
        - 后续每行：一个步骤（不含序号、符号、标点前缀）
        不要有任何前言、解释或额外说明，直接输出内容。
        """

    // MARK: - Testable static helpers

    static func parseSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let jsonStr = String(line.dropFirst(6))
        guard jsonStr != "[DONE]",
              let data = jsonStr.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data),
              let content = chunk.choices.first?.delta.content else { return nil }
        return content
    }

    static func extractLines(buffer: String, appending content: String) -> (lines: [String], remaining: String) {
        var buf = buffer + content
        var lines: [String] = []
        while let newlineIndex = buf.firstIndex(of: "\n") {
            let line = String(buf[buf.startIndex..<newlineIndex])
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(line)
            }
            buf = String(buf[buf.index(after: newlineIndex)...])
        }
        return (lines, buf)
    }

    // MARK: - Stream

    func streamPlan(description: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = KeychainService.shared.loadAPIKey(), !apiKey.isEmpty else {
                        continuation.finish(throwing: OpenAIError.noAPIKey)
                        return
                    }

                    var request = URLRequest(url: OpenAIService.endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body = OpenAIRequest(
                        model: "gpt-4o-mini",
                        messages: [
                            .init(role: "system", content: OpenAIService.systemPrompt),
                            .init(role: "user", content: description)
                        ],
                        stream: true,
                        maxTokens: 512
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: OpenAIError.invalidResponse)
                        return
                    }
                    guard http.statusCode == 200 else {
                        continuation.finish(throwing: OpenAIError.httpError(http.statusCode))
                        return
                    }

                    var buffer = ""
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        guard let content = OpenAIService.parseSSELine(line) else { continue }
                        let (newLines, newBuf) = OpenAIService.extractLines(buffer: buffer, appending: content)
                        buffer = newBuf
                        for extracted in newLines { continuation.yield(extracted) }
                    }
                    // Flush remaining buffer
                    let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { continuation.yield(trimmed) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

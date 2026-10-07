import Foundation

/// Talks to an OpenAI-compatible `/chat/completions` endpoint, sends the user's prompt
/// with registered tool declarations, and feeds each returned tool call through
/// `AIAgentDispatcher`.
///
/// Designed around Swift concurrency (`async`/`await`) and native `URLSession` — no
/// third-party dependencies.
@MainActor
final class AIService {

    // MARK: - Error types

    enum ServiceError: LocalizedError {
        case notConfigured
        case invalidEndpoint
        case httpError(statusCode: Int, body: String)
        case decodingError(String)
        case noResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured:                  "AI is not configured. Set your API key in AI Settings."
            case .invalidEndpoint:                "The base URL is invalid."
            case .httpError(let code, let body):  "HTTP \(code): \(body)"
            case .decodingError(let detail):      "Failed to decode response: \(detail)"
            case .noResponse:                     "The model returned no actionable content."
            }
        }
    }

    // MARK: - Dependencies

    private let config: AIConfig
    private let dispatcher: AIAgentDispatcher

    init(config: AIConfig? = nil, dispatcher: AIAgentDispatcher) {
        self.config = config ?? AIConfig.shared
        self.dispatcher = dispatcher
    }

    // MARK: - Public API

    /// Send a natural-language instruction, let the model decide which tools to call, and
    /// execute them.
    ///
    /// - Parameter prompt: The user's instruction, e.g. "Flip my layer horizontally".
    /// - Returns: The assistant's final text reply (may be empty when every action was a tool call).
    @discardableResult
    func send(prompt: String) async throws -> String {
        guard config.isConfigured else { throw ServiceError.notConfigured }
        guard let url = config.chatCompletionsURL else { throw ServiceError.invalidEndpoint }

        let systemPrompt = """
        You are an image-editing assistant embedded in the Compositor macOS app.
        Use the provided tools to carry out the user's instructions.
        If multiple tools are needed, call them one after another.
        Reply in the same language the user writes in.

        CRITICAL WORKFLOW RULES FOR REMOVING OBJECTS / INPAINTING / ERASING:
        - When the user asks to remove, erase, or inpaint people, objects, backgrounds, or watermarks:
          1. Try segmenting the target using `select_subject`, or `rect_selection` if coordinates are known.
          2. If `select_subject` fails or reports that no distinct subject was detected, ABSOLUTELY NEVER call `select_all`! Calling `select_all` will regenerate or clear the entire image, which is prohibited.
          3. Instead, immediately reply directly to the user, advising them to use the Lasso (套索) or Rectangular (矩形选框) selection tool to outline the target area manually first.
          4. Once an active local selection exists, execute `ai_generative_fill` to inpaint and remove the selected element.
        """

        // Build the initial conversation with the system prompt.
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt]
        ]

        // Iterate: the model may return tool calls that need results fed back.
        let maxRounds = 8
        let model = config.model
        let apiKey = config.apiKey
        let tools = CommandRegistry.shared.openAITools()
        for _ in 0..<maxRounds {
            let (reply, toolCalls) = try await chatCompletion(
                url: url,
                model: model,
                apiKey: apiKey,
                messages: messages,
                tools: tools
            )

            // No tool calls: we're done.
            guard let toolCalls, !toolCalls.isEmpty else {
                return reply ?? ""
            }

            // Append the assistant message that contained the tool calls.
            var assistantMessage: [String: Any] = ["role": "assistant"]
            if let reply { assistantMessage["content"] = reply }
            assistantMessage["tool_calls"] = toolCalls.map { tc -> [String: Any] in
                [
                    "id": tc.id,
                    "type": "function",
                    "function": [
                        "name": tc.name,
                        "arguments": tc.rawArguments
                    ] as [String: Any]
                ]
            }
            messages.append(assistantMessage)

            // Execute each tool call and feed results back.
            for tc in toolCalls {
                let result: String
                do {
                    let args = try parseArguments(tc.rawArguments)
                    result = try await dispatcher.execute(toolCallName: tc.name, arguments: args)
                } catch {
                    result = "Error: \(error.localizedDescription)"
                }
                messages.append([
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": result
                ])
            }
        }

        // If we hit the round limit, return the last reply we got.
        return ""
    }

    // MARK: - Network layer

    /// A single parsed tool call from the response.
    private struct ToolCall {
        let id: String
        let name: String
        let rawArguments: String
    }

    /// Perform one `POST /chat/completions` round-trip and return the reply text and any
    /// tool calls.
    private nonisolated func chatCompletion(
        url: URL,
        model: String,
        apiKey: String,
        messages: [[String: Any]],
        tools: [[String: Any]]
    ) async throws -> (reply: String?, toolCalls: [ToolCall]?) {
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "tools": tools,
            "tool_choice": "auto"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.noResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "(unreadable)"
            throw ServiceError.httpError(statusCode: http.statusCode, body: responseBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw ServiceError.decodingError("Unexpected response structure.")
        }

        let reply = message["content"] as? String

        var toolCalls: [ToolCall]?
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            toolCalls = rawCalls.compactMap { call in
                guard let id = call["id"] as? String,
                      let fn = call["function"] as? [String: Any],
                      let name = fn["name"] as? String,
                      let args = fn["arguments"] as? String else { return nil }
                return ToolCall(id: id, name: name, rawArguments: args)
            }
        }

        return (reply, toolCalls)
    }

    // MARK: - Argument parsing

    private func parseArguments(_ raw: String) throws -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.decodingError("Tool call arguments are not valid JSON: \(raw)")
        }
        return obj
    }
}

import Foundation

/// Dispatches AI tool calls to domain commands registered in `CommandRegistry`.
///
/// Executes on `@MainActor` to safely mutate `EditorSession` and commit steps into
/// undo/redo history. Supports single-step execution and serial composite pipelines.
@MainActor
final class AIAgentDispatcher {

    private let session: EditorSession
    private let registry: CommandRegistry

    init(session: EditorSession, registry: CommandRegistry? = nil) {
        self.session = session
        self.registry = registry ?? CommandRegistry.shared
    }

    // MARK: - Public Execution API

    /// Execute a single tool call returned by the model.
    /// Intercepts and suppresses app-level UI modal alert flags (`brushError`, `cropError`),
    /// allowing failures to be cleanly reported to the model conversation instead of popping
    /// up intrusive system modal dialogs on the user's screen.
    @discardableResult
    func execute(toolCallName: String, arguments: [String: Any]) async throws -> String {
        guard let command = registry.command(named: toolCallName) else {
            throw CommandError.invalidArgument("Unrecognized tool name: '\(toolCallName)'. No matching command registered.")
        }

        // Clear any previous error flags before running command
        session.brushError = nil
        session.cropError = nil

        do {
            let result = try await command.execute(arguments: arguments, on: session)

            // If the underlying operation recorded an error on the session, intercept it
            if let err = session.brushError {
                session.brushError = nil // Suppress modal popup
                throw CommandError.executionFailed(err)
            }
            if let err = session.cropError {
                session.cropError = nil // Suppress modal popup
                throw CommandError.executionFailed(err)
            }

            return result
        } catch {
            // Ensure UI modal alerts remain suppressed if command throws
            session.brushError = nil
            session.cropError = nil
            throw error
        }
    }

    /// Serial execution for composite tool chains (e.g. "Select Subject" -> "Invert" -> "Fill Red").
    /// - Parameter toolCalls: Ordered list of tool names and parsed arguments.
    /// - Returns: Array of output messages in execution order.
    @discardableResult
    func executeSeries(_ toolCalls: [(name: String, arguments: [String: Any])]) async throws -> [String] {
        var results: [String] = []
        for call in toolCalls {
            let output = try await execute(toolCallName: call.name, arguments: call.arguments)
            results.append(output)
        }
        return results
    }
}

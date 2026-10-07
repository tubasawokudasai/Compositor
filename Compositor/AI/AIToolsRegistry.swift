import Foundation

/// Unified bridge providing OpenAI Function Calling tools declarations.
/// Forwards to the unified `CommandRegistry`.
enum AIToolsRegistry {
    /// Returns the array of tool declarations conforming to the OpenAI Function Calling schema.
    @MainActor
    static var tools: [[String: Any]] {
        CommandRegistry.shared.openAITools()
    }
}

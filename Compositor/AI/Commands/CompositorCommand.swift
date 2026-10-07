import Foundation

/// Major domain categories for Compositor actions.
enum CommandCategory: String, CaseIterable, Sendable {
    case layer = "Layers & Transform"
    case adjustment = "Color & Adjustments"
    case selection = "Selection & Mask"
    case canvas = "Canvas Control"
    case fillAndGen = "Generation & Fill"
}

/// Errors thrown by command execution or argument validation.
enum CommandError: LocalizedError {
    case missingArgument(String)
    case invalidArgument(String)
    case preconditionFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name): return "Missing required argument: '\(name)'."
        case .invalidArgument(let msg): return "Invalid argument: \(msg)"
        case .preconditionFailed(let msg): return "Precondition failed: \(msg)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        }
    }
}

/// A unified domain action that can be registered, exported to OpenAI Function Calling schema,
/// and executed against an `EditorSession`.
@MainActor
protocol CompositorCommand: Sendable {
    /// Unique function name matching the OpenAI tool call identifier, e.g. "flip_layer".
    var name: String { get }

    /// Human-readable description of what the action does.
    var description: String { get }

    /// Organization category.
    var category: CommandCategory { get }

    /// JSON Schema parameters dictionary conforming to OpenAI Function Calling format.
    var parametersSchema: [String: Any] { get }

    /// Safely executes the action on the provided `EditorSession`.
    /// - Parameters:
    ///   - arguments: The parsed JSON arguments from the model.
    ///   - session: The active editor session.
    /// - Returns: A result message to return to the model/user.
    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String
}

extension CompositorCommand {
    /// Generates the standard OpenAI function tool declaration.
    var openAIToolDeclaration: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parametersSchema
            ] as [String: Any]
        ]
    }
}

/// Helper for constructing JSON Schemas cleanly and concisely.
enum SchemaBuilder {
    static func object(
        properties: [String: [String: Any]],
        required: [String] = []
    ) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
    }

    static func string(description: String, enumValues: [String]? = nil) -> [String: Any] {
        var dict: [String: Any] = [
            "type": "string",
            "description": description
        ]
        if let enumValues { dict["enum"] = enumValues }
        return dict
    }

    static func number(description: String, minimum: Double? = nil, maximum: Double? = nil) -> [String: Any] {
        var dict: [String: Any] = [
            "type": "number",
            "description": description
        ]
        if let minimum { dict["minimum"] = minimum }
        if let maximum { dict["maximum"] = maximum }
        return dict
    }

    static func integer(description: String, minimum: Int? = nil, maximum: Int? = nil) -> [String: Any] {
        var dict: [String: Any] = [
            "type": "integer",
            "description": description
        ]
        if let minimum { dict["minimum"] = minimum }
        if let maximum { dict["maximum"] = maximum }
        return dict
    }

    static func boolean(description: String) -> [String: Any] {
        [
            "type": "boolean",
            "description": description
        ]
    }
}

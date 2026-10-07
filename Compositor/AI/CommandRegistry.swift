import Foundation

/// Central registry managing all domain commands available to the AI agent.
///
/// Follows the Command Pattern: rather than hardcoding dispatch handlers across switch statements,
/// each capability is encapsulated as an independent `CompositorCommand`. New commands can be
/// registered at runtime without modifying the dispatcher or network layer.
@MainActor
final class CommandRegistry {
    static let shared = CommandRegistry()

    private(set) var commands: [String: any CompositorCommand] = [:]

    init() {
        registerDefaults()
    }

    // MARK: - Registration API

    /// Register a single command into the registry.
    func register(_ command: any CompositorCommand) {
        commands[command.name] = command
    }

    /// Register multiple commands at once.
    func register(_ commandList: [any CompositorCommand]) {
        for command in commandList {
            register(command)
        }
    }

    /// Retrieve a command by its unique tool name.
    func command(named name: String) -> (any CompositorCommand)? {
        commands[name]
    }

    /// Returns all registered commands grouped by category.
    func commands(for category: CommandCategory) -> [any CompositorCommand] {
        commands.values.filter { $0.category == category }
    }

    /// Export all registered commands into the OpenAI Function Calling `tools` JSON array format.
    func openAITools() -> [[String: Any]] {
        commands.values.map { $0.openAIToolDeclaration }
    }

    // MARK: - Default Commands

    private func registerDefaults() {
        // a. Layers & Transform
        register([
            AddBlankLayerCommand(),
            DeleteLayerCommand(),
            DuplicateLayerCommand(),
            RenameLayerCommand(),
            FlipLayerCommand(),
            SetLayerOpacityCommand(),
            SetBlendModeCommand(),
            ToggleLayerVisibilityCommand()
        ])

        // b. Color & Adjustments
        register([
            HueSaturationCommand(),
            LevelsCommand(),
            CurvesCommand(),
            InvertColorsCommand()
        ])

        // c. Selection & Mask
        register([
            SelectAllCommand(),
            DeselectCommand(),
            InvertSelectionCommand(),
            SelectSubjectCommand(),
            RectSelectionCommand(),
            AddLayerMaskCommand()
        ])

        // d. Canvas Control
        register([
            CropCanvasCommand(),
            ResizeCanvasCommand(),
            TrimEdgesCommand()
        ])

        // e. Generation & Fill
        register([
            FillColorCommand(),
            AIGenerativeFillCommand()
        ])
    }
}

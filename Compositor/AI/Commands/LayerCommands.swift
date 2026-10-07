import Foundation

// MARK: - Add Blank Layer

struct AddBlankLayerCommand: CompositorCommand {
    let name = "add_blank_layer"
    let description = "Insert a new blank layer directly above the current active layer."
    let category: CommandCategory = .layer

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "name": SchemaBuilder.string(description: "Optional custom name for the new layer.")
        ]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canEditLayers else {
            throw CommandError.preconditionFailed("Cannot add a layer right now (no active document or project is busy).")
        }
        session.addBlankLayer()
        if let customName = arguments["name"] as? String,
           !customName.trimmingCharacters(in: .whitespaces).isEmpty,
           let id = session.activeLayerID {
            session.renameLayer(id, to: customName)
            return "Created new layer '\(customName)'."
        }
        let layerName = session.activeLayer?.name ?? "New Layer"
        return "Created blank layer '\(layerName)'."
    }
}

// MARK: - Delete Layer

struct DeleteLayerCommand: CompositorCommand {
    let name = "delete_layer"
    let description = "Delete the currently active layer or all selected layers."
    let category: CommandCategory = .layer

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canEditLayers, session.activeLayer != nil else {
            throw CommandError.preconditionFailed("No active layer available to delete.")
        }
        let name = session.activeLayer?.name ?? "Layer"
        session.deleteSelectedLayers()
        return "Deleted layer '\(name)'."
    }
}

// MARK: - Duplicate Layer

struct DuplicateLayerCommand: CompositorCommand {
    let name = "duplicate_layer"
    let description = "Duplicate the active layer or current selection onto a new layer."
    let category: CommandCategory = .layer

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canEditLayers, session.activeLayer != nil else {
            throw CommandError.preconditionFailed("No active layer available to duplicate.")
        }
        let originalName = session.activeLayer?.name ?? "Layer"
        session.layerViaCopy()
        let newName = session.activeLayer?.name ?? "Copy"
        return "Duplicated '\(originalName)' into '\(newName)'."
    }
}

// MARK: - Rename Layer

struct RenameLayerCommand: CompositorCommand {
    let name = "rename_layer"
    let description = "Rename the currently active layer."
    let category: CommandCategory = .layer

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "name": SchemaBuilder.string(description: "New name for the layer.")
        ],
        required: ["name"]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard let newName = arguments["name"] as? String, !newName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CommandError.missingArgument("name")
        }
        guard let id = session.activeLayerID else {
            throw CommandError.preconditionFailed("No active layer selected to rename.")
        }
        let oldName = session.activeLayer?.name ?? "Layer"
        session.renameLayer(id, to: newName)
        return "Renamed layer '\(oldName)' to '\(newName)'."
    }
}

// MARK: - Flip Layer

struct FlipLayerCommand: CompositorCommand {
    let name = "flip_layer"
    let description = "Flip the active layer horizontally or vertically across its center."
    let category: CommandCategory = .layer

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "direction": SchemaBuilder.string(
                description: "Axis to flip across.",
                enumValues: ["horizontal", "vertical"]
            )
        ],
        required: ["direction"]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard let direction = arguments["direction"] as? String else {
            throw CommandError.missingArgument("direction")
        }
        let horizontally: Bool
        switch direction {
        case "horizontal": horizontally = true
        case "vertical": horizontally = false
        default: throw CommandError.invalidArgument("direction must be 'horizontal' or 'vertical'.")
        }
        guard session.canTransform else {
            throw CommandError.preconditionFailed("No pixel layer available to flip (cannot transform blank or non-visible layers).")
        }
        session.flipLayers(horizontally: horizontally)
        return "Flipped layer \(horizontally ? "horizontally" : "vertically")."
    }
}

// MARK: - Set Layer Opacity

struct SetLayerOpacityCommand: CompositorCommand {
    let name = "set_layer_opacity"
    let description = "Set opacity of the active layer between 0.0 (transparent) and 1.0 (opaque)."
    let category: CommandCategory = .layer

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "opacity": SchemaBuilder.number(
                description: "Opacity value between 0.0 and 1.0.",
                minimum: 0.0,
                maximum: 1.0
            )
        ],
        required: ["opacity"]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard let opacity = arguments["opacity"] as? Double else {
            throw CommandError.missingArgument("opacity")
        }
        guard opacity >= 0.0 && opacity <= 1.0 else {
            throw CommandError.invalidArgument("opacity must be between 0.0 and 1.0.")
        }
        guard session.canEditOpacity else {
            throw CommandError.preconditionFailed("Cannot adjust opacity for the current selection or mode.")
        }
        session.setLayerOpacity(opacity)
        return "Layer opacity set to \(Int((opacity * 100).rounded()))%."
    }
}

// MARK: - Set Blend Mode

struct SetBlendModeCommand: CompositorCommand {
    let name = "set_blend_mode"
    let description = "Set the blend mode of the active layer. Supported modes include Normal, Multiply, Screen, Overlay, etc."
    let category: CommandCategory = .layer

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "mode": SchemaBuilder.string(
                description: "Name of the blend mode (e.g. 'Multiply', 'Screen', 'Overlay').",
                enumValues: LayerBlendMode.allCases.map(\.rawValue)
            )
        ],
        required: ["mode"]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard let modeName = arguments["mode"] as? String else {
            throw CommandError.missingArgument("mode")
        }
        guard let mode = LayerBlendMode(rawValue: modeName) else {
            throw CommandError.invalidArgument("Unrecognized blend mode '\(modeName)'. Available: \(LayerBlendMode.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        guard session.canEditAppearance else {
            throw CommandError.preconditionFailed("Cannot change appearance for the active layer.")
        }
        session.setLayerBlendMode(mode)
        return "Layer blend mode set to \(mode.rawValue)."
    }
}

// MARK: - Toggle Layer Visibility

struct ToggleLayerVisibilityCommand: CompositorCommand {
    let name = "toggle_layer_visibility"
    let description = "Toggle the visibility (show/hide) of the currently active layer."
    let category: CommandCategory = .layer

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard let id = session.activeLayerID else {
            throw CommandError.preconditionFailed("No active layer to toggle.")
        }
        guard session.canEditLayers else {
            throw CommandError.preconditionFailed("Cannot toggle visibility right now.")
        }
        session.toggleLayerVisibility(id)
        let visible = session.document?.layers.first { $0.id == id }?.isVisible ?? true
        return "Layer is now \(visible ? "visible" : "hidden")."
    }
}

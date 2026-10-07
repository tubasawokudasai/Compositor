import Foundation

// MARK: - Hue / Saturation

struct HueSaturationCommand: CompositorCommand {
    let name = "adjust_hue_saturation"
    let description = "Add or adjust a Hue/Saturation adjustment layer with hue, saturation, and lightness shifts."
    let category: CommandCategory = .adjustment

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "hue": SchemaBuilder.number(
                description: "Hue shift from -180.0 to 180.0 degrees (default 0).",
                minimum: -180.0,
                maximum: 180.0
            ),
            "saturation": SchemaBuilder.number(
                description: "Saturation adjustment from -100.0 to 100.0 (default 0).",
                minimum: -100.0,
                maximum: 100.0
            ),
            "lightness": SchemaBuilder.number(
                description: "Lightness adjustment from -100.0 to 100.0 (default 0).",
                minimum: -100.0,
                maximum: 100.0
            ),
            "colorize": SchemaBuilder.boolean(description: "Convert the image to a monochromatic tint.")
        ]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canEditLayers else {
            throw CommandError.preconditionFailed("Cannot edit layers right now.")
        }
        let hue = arguments["hue"] as? Double ?? 0.0
        let saturation = arguments["saturation"] as? Double ?? 0.0
        let lightness = arguments["lightness"] as? Double ?? 0.0
        let colorize = arguments["colorize"] as? Bool ?? false

        session.addAdjustment(.hsv)
        if let id = session.activeLayerID, var adj = session.activeLayer?.adjustment {
            adj.hsvSettings = HueSaturationSettings(hue: hue, saturation: saturation, lightness: lightness, colorize: colorize)
            adj.hue = hue
            adj.saturation = saturation
            adj.lightness = lightness
            adj.colorize = colorize
            session.updateAdjustment(id, value: adj)
        }
        session.adjustmentEditingID = nil
        return "Added Hue/Saturation adjustment (Hue: \(Int(hue))°, Saturation: \(Int(saturation)), Lightness: \(Int(lightness)))."
    }
}

// MARK: - Levels

struct LevelsCommand: CompositorCommand {
    let name = "adjust_levels"
    let description = "Add a Levels adjustment layer to adjust shadow, midtone (gamma), and highlight tonal ranges."
    let category: CommandCategory = .adjustment

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "blackPoint": SchemaBuilder.number(
                description: "Input shadow floor from 0 to 254 (default 0).",
                minimum: 0,
                maximum: 254
            ),
            "whitePoint": SchemaBuilder.number(
                description: "Input highlight ceiling from 1 to 255 (default 255).",
                minimum: 1,
                maximum: 255
            ),
            "gamma": SchemaBuilder.number(
                description: "Midtone gamma multiplier from 0.1 to 9.99 (default 1.0).",
                minimum: 0.1,
                maximum: 9.99
            )
        ]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canEditLayers else {
            throw CommandError.preconditionFailed("Cannot edit layers right now.")
        }
        let black = arguments["blackPoint"] as? Double ?? 0.0
        let white = arguments["whitePoint"] as? Double ?? 255.0
        let gamma = arguments["gamma"] as? Double ?? 1.0

        session.addAdjustment(.levels)
        if let id = session.activeLayerID, var adj = session.activeLayer?.adjustment {
            var levels = LevelsSettings()
            levels.current = LevelRange(black: black, gamma: gamma, white: white).normalized
            adj.levels = levels
            session.updateAdjustment(id, value: adj)
        }
        session.adjustmentEditingID = nil
        return "Added Levels adjustment (Shadow: \(Int(black)), Highlight: \(Int(white)), Gamma: \(String(format: "%.2f", gamma)))."
    }
}

// MARK: - Curves

struct CurvesCommand: CompositorCommand {
    let name = "adjust_curves"
    let description = "Add a Curves adjustment layer to control tonal curve mapping."
    let category: CommandCategory = .adjustment

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canEditLayers else {
            throw CommandError.preconditionFailed("Cannot edit layers right now.")
        }
        session.addAdjustment(.curves)
        session.adjustmentEditingID = nil
        return "Added Curves adjustment layer."
    }
}

// MARK: - Invert Colors

struct InvertColorsCommand: CompositorCommand {
    let name = "invert_colors"
    let description = "Invert colors. Inverts the pixels of the active layer if rasterized, or adds an Invert adjustment layer."
    let category: CommandCategory = .adjustment

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        if session.canInvert {
            await session.invertPixels()
            return "Inverted active layer pixels."
        } else if session.canEditLayers {
            session.addAdjustment(.invert)
            session.adjustmentEditingID = nil
            return "Added Invert adjustment layer."
        } else {
            throw CommandError.preconditionFailed("Cannot invert colors in current document state.")
        }
    }
}

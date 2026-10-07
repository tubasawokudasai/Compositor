import Foundation
import CoreGraphics

// MARK: - Select All

struct SelectAllCommand: CompositorCommand {
    let name = "select_all"
    let description = "Select the entire canvas boundaries."
    let category: CommandCategory = .selection

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.document != nil else {
            throw CommandError.preconditionFailed("No active document open.")
        }
        session.selectAll()
        return "Selected all pixels in canvas."
    }
}

// MARK: - Deselect

struct DeselectCommand: CompositorCommand {
    let name = "deselect"
    let description = "Clear the current active selection."
    let category: CommandCategory = .selection

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.selection != nil else {
            return "No selection was active."
        }
        session.deselect()
        return "Cleared selection."
    }
}

// MARK: - Invert Selection

struct InvertSelectionCommand: CompositorCommand {
    let name = "invert_selection"
    let description = "Invert the current selection outline."
    let category: CommandCategory = .selection

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.selection != nil else {
            throw CommandError.preconditionFailed("Cannot invert selection because no selection is currently active.")
        }
        session.invertSelection()
        return "Inverted selection outline."
    }
}

// MARK: - Select Subject

struct SelectSubjectCommand: CompositorCommand {
    let name = "select_subject"
    let description = "Use Vision AI to automatically segment and select the primary foreground subject. If no distinct subject is found, use rect_selection or lasso selection instead."
    let category: CommandCategory = .selection

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canSelectSubject else {
            session.brushError = nil
            return "Error: No distinct subject detected on this layer. Please use the Lasso or Rectangular selection tool to outline the target area first."
        }
        session.brushError = nil
        do {
            let found = try await session.performSelectSubject()
            session.brushError = nil
            guard found, let selection = session.selection, !selection.isEmpty else {
                return "Error: No distinct subject detected on this layer. Please use the Lasso or Rectangular selection tool to outline the target area first."
            }
            return "Identified and selected primary subject."
        } catch {
            session.brushError = nil
            return "Error: No distinct subject detected on this layer. Please use the Lasso or Rectangular selection tool to outline the target area first."
        }
    }
}

// MARK: - Rectangular Selection

struct RectSelectionCommand: CompositorCommand {
    let name = "rect_selection"
    let description = "Create a rectangular selection with specific coordinates and dimensions."
    let category: CommandCategory = .selection

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "x": SchemaBuilder.number(description: "X origin in canvas pixels."),
            "y": SchemaBuilder.number(description: "Y origin in canvas pixels."),
            "width": SchemaBuilder.number(description: "Width in canvas pixels.", minimum: 1),
            "height": SchemaBuilder.number(description: "Height in canvas pixels.", minimum: 1)
        ],
        required: ["x", "y", "width", "height"]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard let document = session.document else {
            throw CommandError.preconditionFailed("No active document.")
        }
        guard let x = arguments["x"] as? Double,
              let y = arguments["y"] as? Double,
              let width = arguments["width"] as? Double,
              let height = arguments["height"] as? Double,
              width > 0, height > 0 else {
            throw CommandError.invalidArgument("Coordinates (x, y, width, height) must specify a positive rectangular area.")
        }
        let rect = CGRect(x: x, y: y, width: width, height: height)
            .intersection(CGRect(origin: .zero, size: document.size))
        guard !rect.isNull && !rect.isEmpty else {
            throw CommandError.invalidArgument("Selection rect falls completely outside the canvas.")
        }
        let path = CGPath(rect: rect, transform: nil)
        session.setSelection(DocumentSelection(path: path), name: "Marquee Selection")
        return "Selected region [\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width)) × \(Int(rect.height))]."
    }
}

// MARK: - Add Layer Mask

struct AddLayerMaskCommand: CompositorCommand {
    let name = "add_layer_mask"
    let description = "Add a mask to the active layer. If a selection is active, it creates a mask revealing the selected region."
    let category: CommandCategory = .selection

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "revealing": SchemaBuilder.boolean(description: "True to reveal content by default; false to conceal/hide (default: true).")
        ]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canEditLayers, session.activeLayer != nil else {
            throw CommandError.preconditionFailed("No active layer available to attach a mask.")
        }
        let revealing = arguments["revealing"] as? Bool ?? true
        let hadSelection = session.selection != nil
        session.addLayerMask(revealing: revealing)
        if hadSelection {
            return "Created layer mask from active selection."
        } else {
            return "Added \(revealing ? "reveal-all (white)" : "hide-all (black)") layer mask."
        }
    }
}

import Foundation
import CoreGraphics

// MARK: - Crop Canvas

struct CropCanvasCommand: CompositorCommand {
    let name = "crop_canvas"
    let description = "Crop the document canvas to specified coordinates, or crop to the current selection bounds if no coordinates are given."
    let category: CommandCategory = .canvas

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "x": SchemaBuilder.number(description: "Left coordinate of crop bounding box (optional if selection is active)."),
            "y": SchemaBuilder.number(description: "Top coordinate of crop bounding box (optional if selection is active)."),
            "width": SchemaBuilder.number(description: "Width of crop area (optional if selection is active).", minimum: 1),
            "height": SchemaBuilder.number(description: "Height of crop area (optional if selection is active).", minimum: 1)
        ]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canStartProjectOperation, let docSize = session.document?.size else {
            throw CommandError.preconditionFailed("No active document or canvas is busy.")
        }
        let cropTarget: CGRect
        if let x = arguments["x"] as? Double,
           let y = arguments["y"] as? Double,
           let width = arguments["width"] as? Double,
           let height = arguments["height"] as? Double {
            cropTarget = CGRect(x: x, y: y, width: width, height: height)
        } else if let selection = session.selection, !selection.isEmpty {
            cropTarget = selection.path.boundingBoxOfPath.integral.intersection(CGRect(origin: .zero, size: docSize))
        } else {
            throw CommandError.missingArgument("Specify (x, y, width, height) or make an active selection before cropping.")
        }
        guard CropGeometry.valid(cropTarget) else {
            throw CommandError.invalidArgument("Crop dimensions must be at least 1×1 pixel within valid bounds.")
        }
        session.cropRect = cropTarget
        await session.commitCrop()
        if session.cropError != nil {
            let msg = session.cropError ?? "Crop failed"
            session.cropError = nil
            throw CommandError.executionFailed(msg)
        }
        return "Cropped canvas to [\(Int(cropTarget.width)) × \(Int(cropTarget.height)) px]."
    }
}

// MARK: - Resize Canvas

struct ResizeCanvasCommand: CompositorCommand {
    let name = "resize_canvas"
    let description = "Resize canvas dimensions with an anchor point without scaling layer content."
    let category: CommandCategory = .canvas

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "width": SchemaBuilder.integer(description: "New width in pixels.", minimum: 1),
            "height": SchemaBuilder.integer(description: "New height in pixels.", minimum: 1),
            "anchor": SchemaBuilder.integer(
                description: "Anchor position 0-8: 0=Top-Left, 1=Top-Center, 2=Top-Right, 3=Middle-Left, 4=Center (default), 5=Middle-Right, 6=Bottom-Left, 7=Bottom-Center, 8=Bottom-Right.",
                minimum: 0,
                maximum: 8
            )
        ],
        required: ["width", "height"]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canStartProjectOperation, let snapshot = session.projectSnapshot() else {
            throw CommandError.preconditionFailed("Cannot resize canvas in current state.")
        }
        guard let width = arguments["width"] as? Int, width >= 1,
              let height = arguments["height"] as? Int, height >= 1 else {
            throw CommandError.invalidArgument("Width and height must be positive integers.")
        }
        let anchor = arguments["anchor"] as? Int ?? 4

        let options = CanvasSizeOptions(width: width, height: height, anchor: anchor)
        session.isProjectBusy = true
        defer { session.isProjectBusy = false }

        do {
            let result = try await CanvasResizer.shared.resize(snapshot, to: options)
            session.applyDocumentSize(result, actionName: "Canvas Size")
            return "Canvas resized to \(width) × \(height) pixels."
        } catch {
            throw CommandError.executionFailed("Failed to resize canvas: \(error.localizedDescription)")
        }
    }
}

// MARK: - Trim Edges

struct TrimEdgesCommand: CompositorCommand {
    let name = "trim_edges"
    let description = "Automatically trim surrounding transparent pixel boundaries from the canvas."
    let category: CommandCategory = .canvas

    let parametersSchema = SchemaBuilder.object(properties: [:])

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canStartProjectOperation else {
            throw CommandError.preconditionFailed("Cannot trim canvas in current state.")
        }
        let trimmed = try await session.trim(options: TrimOptions())
        if trimmed {
            let size = session.document?.size ?? .zero
            return "Trimmed transparent borders. New canvas size: \(Int(size.width)) × \(Int(size.height)) px."
        } else {
            return "Canvas already has no transparent borders to trim."
        }
    }
}

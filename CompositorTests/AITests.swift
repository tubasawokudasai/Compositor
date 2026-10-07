import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import Compositor

@MainActor
struct AITests {

    // MARK: - AIConfig Tests

    @Test func configEndpointResolution() {
        let config = AIConfig.shared
        config.baseURL = "https://api.openai.com/v1/"
        #expect(config.chatCompletionsURL?.absoluteString == "https://api.openai.com/v1/chat/completions")

        config.baseURL = "https://custom.ai-proxy.org/v1"
        #expect(config.chatCompletionsURL?.absoluteString == "https://custom.ai-proxy.org/v1/chat/completions")

        config.baseURL = "http://localhost:11434/v1"
        #expect(config.chatCompletionsURL?.absoluteString == "http://localhost:11434/v1/chat/completions")
    }

    // MARK: - CommandRegistry Tests

    @Test func registryCategorizationAndExport() {
        let registry = CommandRegistry.shared

        // Verify all 5 categories are populated
        #expect(!registry.commands(for: .layer).isEmpty)
        #expect(!registry.commands(for: .adjustment).isEmpty)
        #expect(!registry.commands(for: .selection).isEmpty)
        #expect(!registry.commands(for: .canvas).isEmpty)
        #expect(!registry.commands(for: .fillAndGen).isEmpty)

        // Verify total exported tools
        let tools = registry.openAITools()
        #expect(tools.count >= 20)

        // Verify tool schema structure conforms to OpenAI Function Calling standard
        for tool in tools {
            #expect(tool["type"] as? String == "function")
            guard let fn = tool["function"] as? [String: Any] else {
                Issue.record("Tool declaration missing function object")
                continue
            }
            #expect(!(fn["name"] as? String ?? "").isEmpty)
            #expect(!(fn["description"] as? String ?? "").isEmpty)
            #expect(fn["parameters"] is [String: Any])
        }
    }

    // MARK: - AIAgentDispatcher Layer & Transform Tests

    @Test func dispatcherExecutesLayerModifications() async throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        try insertPaintedLayer(into: session)

        let dispatcher = AIAgentDispatcher(session: session)

        // 1. Flip layer
        let flipResult = try await dispatcher.execute(toolCallName: "flip_layer", arguments: ["direction": "horizontal"])
        #expect(flipResult.contains("horizontally"))

        let flipVertResult = try await dispatcher.execute(toolCallName: "flip_layer", arguments: ["direction": "vertical"])
        #expect(flipVertResult.contains("vertically"))

        // 2. Set opacity
        let opacityResult = try await dispatcher.execute(toolCallName: "set_layer_opacity", arguments: ["opacity": 0.75])
        #expect(opacityResult.contains("75%"))
        #expect(session.activeLayer?.opacity == 0.75)

        // 3. Set blend mode
        let blendResult = try await dispatcher.execute(toolCallName: "set_blend_mode", arguments: ["mode": "Multiply"])
        #expect(blendResult.contains("Multiply"))
        #expect(session.activeLayer?.blendMode == .multiply)

        // 4. Add blank layer
        let initialCount = session.document?.layers.count ?? 0
        let addResult = try await dispatcher.execute(toolCallName: "add_blank_layer", arguments: ["name": "Background Tint"])
        #expect(addResult.contains("Background Tint"))
        #expect((session.document?.layers.count ?? 0) == initialCount + 1)

        // 5. Duplicate layer
        let dupResult = try await dispatcher.execute(toolCallName: "duplicate_layer", arguments: [:])
        #expect(dupResult.contains("Duplicated"))

        // 6. Rename layer
        let renameResult = try await dispatcher.execute(toolCallName: "rename_layer", arguments: ["name": "Final Composite"])
        #expect(renameResult.contains("Final Composite"))
        #expect(session.activeLayer?.name == "Final Composite")

        // 7. Toggle visibility
        let initialVisible = session.activeLayer?.isVisible ?? true
        let toggleResult = try await dispatcher.execute(toolCallName: "toggle_layer_visibility", arguments: [:])
        #expect(session.activeLayer?.isVisible == !initialVisible)
        #expect(toggleResult.contains(initialVisible ? "hidden" : "visible"))
    }

    // MARK: - Color & Adjustments Tests

    @Test func dispatcherExecutesAdjustments() async throws {
        let session = EditorSession()
        session.createDocument(width: 60, height: 60)
        try insertPaintedLayer(into: session)

        let dispatcher = AIAgentDispatcher(session: session)

        // Hue/Saturation
        let hsvResult = try await dispatcher.execute(toolCallName: "adjust_hue_saturation", arguments: [
            "hue": 45.0,
            "saturation": 20.0,
            "lightness": -10.0
        ])
        #expect(hsvResult.contains("Hue/Saturation"))
        #expect(session.activeLayer?.adjustment?.kind == .hsv)

        // Levels
        let levelsResult = try await dispatcher.execute(toolCallName: "adjust_levels", arguments: [
            "blackPoint": 15.0,
            "whitePoint": 240.0,
            "gamma": 1.2
        ])
        #expect(levelsResult.contains("Levels"))
        #expect(session.activeLayer?.adjustment?.kind == .levels)

        // Invert
        let invertResult = try await dispatcher.execute(toolCallName: "invert_colors", arguments: [:])
        #expect(invertResult.contains("Invert"))
    }

    // MARK: - Composite Serial Execution (Selection -> Invert -> Fill)

    @Test func compositeSerialExecutionWorkflow() async throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        try insertPaintedLayer(into: session)

        let dispatcher = AIAgentDispatcher(session: session)

        // "先选择一块区域，然后反选，最后填充红色"
        let chain: [(name: String, arguments: [String: Any])] = [
            ("rect_selection", ["x": 10.0, "y": 10.0, "width": 30.0, "height": 30.0]),
            ("invert_selection", [:]),
            ("fill_color", ["color": "red"]),
            ("deselect", [:])
        ]

        let results = try await dispatcher.executeSeries(chain)
        #expect(results.count == 4)
        #expect(results[0].contains("Selected region"))
        #expect(results[1].contains("Inverted selection"))
        #expect(results[2].contains("Filled with red"))
        #expect(results[3].contains("Cleared selection"))

        // Selection should be cleared at the end of the chain
        #expect(session.selection == nil)

        // History undo check: previous actions should be registered in history
        #expect(session.canUndo)
        session.undo() // undid deselect
        #expect(session.canUndo)
    }

    // MARK: - Canvas Control Tests

    @Test func dispatcherExecutesCanvasControl() async throws {
        let session = EditorSession()
        session.createDocument(width: 80, height: 80)
        try insertPaintedLayer(into: session)

        let dispatcher = AIAgentDispatcher(session: session)

        // Resize Canvas
        let resizeResult = try await dispatcher.execute(toolCallName: "resize_canvas", arguments: [
            "width": 120,
            "height": 100,
            "anchor": 4
        ])
        #expect(resizeResult.contains("resized"))
        #expect(session.document?.width == 120)
        #expect(session.document?.height == 100)

        // Crop Canvas
        let cropResult = try await dispatcher.execute(toolCallName: "crop_canvas", arguments: [
            "x": 10.0,
            "y": 10.0,
            "width": 60.0,
            "height": 60.0
        ])
        #expect(cropResult.contains("Cropped canvas"))
        #expect(session.document?.width == 60)
        #expect(session.document?.height == 60)
    }

    // MARK: - Error Handling Tests

    @Test func dispatcherValidatesArgumentsAndErrors() async {
        let session = EditorSession()
        session.createDocument(width: 50, height: 50)
        session.addBlankLayer()

        let dispatcher = AIAgentDispatcher(session: session)

        // Unknown tool
        await #expect(throws: CommandError.self) {
            try await dispatcher.execute(toolCallName: "non_existent_tool", arguments: [:])
        }

        // Invalid opacity (> 1.0)
        await #expect(throws: CommandError.self) {
            try await dispatcher.execute(toolCallName: "set_layer_opacity", arguments: ["opacity": 1.5])
        }

        // Invalid direction
        await #expect(throws: CommandError.self) {
            try await dispatcher.execute(toolCallName: "flip_layer", arguments: ["direction": "diagonal"])
        }

        // Invalid blend mode
        await #expect(throws: CommandError.self) {
            try await dispatcher.execute(toolCallName: "set_blend_mode", arguments: ["mode": "UnknownMode"])
        }
    }

    // MARK: - Inpainting & Selection Tests

    @Test func selectSubjectSoftErrorFeedback() async throws {
        let session = EditorSession()
        session.createDocument(width: 80, height: 80)
        try insertPaintedLayer(into: session) // Flat red color, no subject

        let dispatcher = AIAgentDispatcher(session: session)
        let result = try await dispatcher.execute(toolCallName: "select_subject", arguments: [:])

        #expect(result.contains("Error: No distinct subject detected on this layer"))
        #expect(result.contains("Please use the Lasso or Rectangular selection tool to outline the target area first."))
        #expect(session.brushError == nil) // Modal alert suppressed!
    }

    @Test func inpaintingMaskGeneratorAlphaAndDimensions() throws {
        let session = EditorSession()
        session.createDocument(width: 100, height: 100)
        try insertPaintedLayer(into: session)

        // Create local selection [20, 20, 40, 40]
        let path = CGPath(rect: CGRect(x: 20, y: 20, width: 40, height: 40), transform: nil)
        session.setSelection(DocumentSelection(path: path), name: "Box Selection")

        let maskData = try #require(try session.activeSelectionInpaintingMaskPNG())
        #expect(!maskData.isEmpty)

        // Verify dimensions and alpha channel of generated mask
        let nsImage = try #require(NSImage(data: maskData))
        let cgImage = try #require(nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 100)

        // Read pixels
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                                             bytesPerRow: 400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let pixelPtr = try #require(context.data?.bindMemory(to: UInt8.self, capacity: 40000))

        // Inside selection (center at x=40, y=40, top-left space)
        // Selected pixels are transparent (alpha = 0)
        let insideOffset = (40 * 400) + (40 * 4)
        let insideAlpha = pixelPtr[insideOffset + 3]
        #expect(insideAlpha == 0)

        // Outside selection (x=5, y=5)
        // Unselected pixels are opaque (alpha = 255)
        let outsideOffset = (5 * 400) + (5 * 4)
        let outsideAlpha = pixelPtr[outsideOffset + 3]
        #expect(outsideAlpha == 255)
    }

    @Test func inpaintingRejectsEmptyAndSelectAll() async throws {
        let session = EditorSession()
        session.createDocument(width: 60, height: 60)
        try insertPaintedLayer(into: session)

        let dispatcher = AIAgentDispatcher(session: session)

        // 1. No selection active
        session.deselect()
        let resultEmpty = try await dispatcher.execute(toolCallName: "ai_generative_fill", arguments: ["prompt": "remove object"])
        #expect(resultEmpty == "Please select a local area using selection tools before removing.")

        // 2. Select All active
        session.selectAll()
        let resultAll = try await dispatcher.execute(toolCallName: "ai_generative_fill", arguments: ["prompt": "remove object"])
        #expect(resultAll == "Please select a local area using selection tools before removing.")
    }

    @Test func applyInpaintedImageAndUndoStack() throws {
        let session = EditorSession()
        session.createDocument(width: 50, height: 50)
        try insertPaintedLayer(into: session)

        let originalLayerCount = session.document?.layers.count ?? 0

        // Create a test 50x50 image
        let context = try #require(CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8,
                                             bytesPerRow: 200, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        let testImage = try #require(context.makeImage())

        // Test 1: Create repair layer
        session.applyInpaintedImage(testImage, createNewLayer: true)
        #expect((session.document?.layers.count ?? 0) == originalLayerCount + 1)
        #expect(session.activeLayer?.name == "Generative Fill")
        #expect(session.canUndo)

        // Test undo
        session.undo()
        #expect((session.document?.layers.count ?? 0) == originalLayerCount)

        // Test 2: In-place layer update
        session.applyInpaintedImage(testImage, createNewLayer: false)
        #expect((session.document?.layers.count ?? 0) == originalLayerCount)
        #expect(session.canUndo)
    }

    // MARK: - Helper

    private func insertPaintedLayer(into session: EditorSession) throws {
        let size = try #require(session.document?.size)
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let image = try #require(context.makeImage())
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Painted layer"))
    }
}

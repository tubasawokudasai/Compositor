import Foundation
import AppKit

// MARK: - Fill Color

struct FillColorCommand: CompositorCommand {
    let name = "fill_color"
    let description = "Fill the active selection (or the entire active layer if no selection is active) with a solid color."
    let category: CommandCategory = .fillAndGen

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "color": SchemaBuilder.string(
                description: "Named color ('red', 'green', 'blue', 'white', 'black', 'foreground', 'background') or hex format ('#FF0000')."
            ),
            "red": SchemaBuilder.number(description: "Red component from 0.0 to 1.0.", minimum: 0.0, maximum: 1.0),
            "green": SchemaBuilder.number(description: "Green component from 0.0 to 1.0.", minimum: 0.0, maximum: 1.0),
            "blue": SchemaBuilder.number(description: "Blue component from 0.0 to 1.0.", minimum: 0.0, maximum: 1.0)
        ]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard session.canEditPixels, session.activeLayer != nil else {
            throw CommandError.preconditionFailed("Cannot paint or fill pixels on the current layer.")
        }

        // 1. Explicit RGB components
        if let r = arguments["red"] as? Double,
           let g = arguments["green"] as? Double,
           let b = arguments["blue"] as? Double {
            session.foregroundColor = PaletteColor(red: r, green: g, blue: b)
            await session.fillSelection(with: .foreground)
            return "Filled with RGB(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)))."
        }

        // 2. Named or hex color
        let colorString = (arguments["color"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased() ?? "foreground"
        switch colorString {
        case "background":
            await session.fillSelection(with: .background)
            return "Filled with background color."

        case "foreground":
            await session.fillSelection(with: .foreground)
            return "Filled with foreground color."

        case "black":
            session.foregroundColor = .black
            await session.fillSelection(with: .foreground)
            return "Filled with black."

        case "white":
            session.foregroundColor = .white
            await session.fillSelection(with: .foreground)
            return "Filled with white."

        case "red":
            session.foregroundColor = PaletteColor(red: 1, green: 0, blue: 0)
            await session.fillSelection(with: .foreground)
            return "Filled with red."

        case "green":
            session.foregroundColor = PaletteColor(red: 0, green: 1, blue: 0)
            await session.fillSelection(with: .foreground)
            return "Filled with green."

        case "blue":
            session.foregroundColor = PaletteColor(red: 0, green: 0, blue: 1)
            await session.fillSelection(with: .foreground)
            return "Filled with blue."

        case "yellow":
            session.foregroundColor = PaletteColor(red: 1, green: 1, blue: 0)
            await session.fillSelection(with: .foreground)
            return "Filled with yellow."

        case "cyan":
            session.foregroundColor = PaletteColor(red: 0, green: 1, blue: 1)
            await session.fillSelection(with: .foreground)
            return "Filled with cyan."

        case "magenta":
            session.foregroundColor = PaletteColor(red: 1, green: 0, blue: 1)
            await session.fillSelection(with: .foreground)
            return "Filled with magenta."

        default:
            // Check hex format
            if colorString.hasPrefix("#"), let hexColor = parseHex(colorString) {
                session.foregroundColor = hexColor
                await session.fillSelection(with: .foreground)
                return "Filled with hex color \(colorString.uppercased())."
            }
            // Default to current foreground
            await session.fillSelection(with: .foreground)
            return "Filled with foreground color."
        }
    }

    private func parseHex(_ hex: String) -> PaletteColor? {
        var str = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if str.count == 6 {
            var rgb: UInt64 = 0
            guard Scanner(string: str).scanHexInt64(&rgb) else { return nil }
            let r = Double((rgb >> 16) & 0xFF) / 255.0
            let g = Double((rgb >> 8) & 0xFF) / 255.0
            let b = Double(rgb & 0xFF) / 255.0
            return PaletteColor(red: r, green: g, blue: b)
        }
        return nil
    }
}

// MARK: - AI Generative Fill (Inpainting)

struct AIGenerativeFillCommand: CompositorCommand {
    let name = "ai_generative_fill"
    let description = "Perform AI inpainting or object removal on the active selection of the current layer."
    let category: CommandCategory = .fillAndGen

    let parametersSchema = SchemaBuilder.object(
        properties: [
            "prompt": SchemaBuilder.string(description: "Natural language description of what to inpaint, replace, or fill in the selected area."),
            "create_new_layer": SchemaBuilder.boolean(description: "True to create a new repair layer on top, false to update active layer in place (default: false).")
        ],
        required: ["prompt"]
    )

    func execute(arguments: [String: Any], on session: EditorSession) async throws -> String {
        guard let prompt = arguments["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CommandError.missingArgument("prompt")
        }
        guard let document = session.document else {
            throw CommandError.preconditionFailed("No active document open.")
        }

        // 1. Validate active selection
        guard let selection = session.selection,
              !selection.isEmpty,
              !selection.isSelectAll(canvasSize: document.size) else {
            return "Please select a local area using selection tools before removing."
        }

        // 2. Validate active layer image content
        guard let activeLayer = session.activeLayer, let originalCGImage = activeLayer.asset?.image else {
            throw CommandError.preconditionFailed("Active layer has no image content to edit.")
        }

        // 3. Extract original image and inpainting mask PNG data
        let imagePNGData: Data
        let maskPNGData: Data
        do {
            imagePNGData = try ImageExporter.encodePNG(originalCGImage)
            maskPNGData = try selection.inpaintingMaskPNG(
                width: originalCGImage.width,
                height: originalCGImage.height,
                canvasSize: document.size,
                layerTransform: activeLayer.transform
            )
        } catch {
            throw CommandError.executionFailed("Failed to encode image or mask for inpainting: \(error.localizedDescription)")
        }

        // 4. Verify AI endpoint configuration
        let config = AIConfig.shared
        guard config.isConfigured else {
            throw CommandError.preconditionFailed("AI is not configured. Set your API key in AI Settings.")
        }
        guard let editsURL = config.imageEditsURL else {
            throw CommandError.preconditionFailed("The image edits endpoint URL is invalid.")
        }

        // 5. Construct multipart/form-data request
        var request = URLRequest(url: editsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendFormField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        func appendFileData(name: String, filename: String, mimeType: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendFileData(name: "image", filename: "image.png", mimeType: "image/png", data: imagePNGData)
        appendFileData(name: "mask", filename: "mask.png", mimeType: "image/png", data: maskPNGData)
        appendFormField(name: "prompt", value: prompt)
        appendFormField(name: "response_format", value: "b64_json")
        let modelName = config.model.lowercased().hasPrefix("gpt") ? "dall-e-2" : config.model
        if !modelName.isEmpty {
            appendFormField(name: "model", value: modelName)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // 6. Execute network request via native URLSession
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CommandError.executionFailed("Failed to reach inpainting service: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CommandError.executionFailed("No response received from inpainting server.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorDetail = String(data: responseData, encoding: .utf8) ?? "Status code \(httpResponse.statusCode)"
            throw CommandError.executionFailed("Inpainting request failed (HTTP \(httpResponse.statusCode)): \(errorDetail)")
        }

        // 7. Parse response (base64 or URL)
        struct ImageEditResponse: Decodable {
            struct Item: Decodable {
                let b64_json: String?
                let url: String?
            }
            let data: [Item]?
        }

        let editResponse: ImageEditResponse
        do {
            editResponse = try JSONDecoder().decode(ImageEditResponse.self, from: responseData)
        } catch {
            throw CommandError.executionFailed("Failed to decode inpainting response JSON: \(error.localizedDescription)")
        }

        guard let firstItem = editResponse.data?.first else {
            throw CommandError.executionFailed("Inpainting response contained no image data.")
        }

        let rawImageData: Data
        if let b64 = firstItem.b64_json, let data = Data(base64Encoded: b64) {
            rawImageData = data
        } else if let urlStr = firstItem.url, let imageURL = URL(string: urlStr) {
            do {
                let (downloaded, _) = try await URLSession.shared.data(from: imageURL)
                rawImageData = downloaded
            } catch {
                throw CommandError.executionFailed("Failed to download inpainting image from URL: \(error.localizedDescription)")
            }
        } else {
            throw CommandError.executionFailed("Response did not provide valid base64 image data or image URL.")
        }

        // 8. Parse into NSImage and extract CGImage
        guard let nsImage = NSImage(data: rawImageData),
              let parsedCGImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CommandError.executionFailed("Failed to parse returned inpainting result into an image.")
        }

        // 9. Resample if necessary to maintain exact layer dimensions
        var finalCGImage = parsedCGImage
        if parsedCGImage.width != originalCGImage.width || parsedCGImage.height != originalCGImage.height {
            if let context = try? BrushRaster.context(width: originalCGImage.width, height: originalCGImage.height, mask: false) {
                context.interpolationQuality = .high
                BrushRaster.draw(parsedCGImage, in: CGRect(x: 0, y: 0, width: originalCGImage.width, height: originalCGImage.height), mask: false, context: context)
                if let scaled = context.makeImage() {
                    finalCGImage = scaled
                }
            }
        }

        // 10. Commit to DocumentHistory (supporting Undo / Redo)
        let createNewLayer = arguments["create_new_layer"] as? Bool ?? false
        session.applyInpaintedImage(finalCGImage, createNewLayer: createNewLayer)
        let targetDesc = createNewLayer ? "created repair layer" : "updated active layer"
        return "Inpainting completed successfully (\(targetDesc)) for prompt: \"\(prompt)\"."
    }
}

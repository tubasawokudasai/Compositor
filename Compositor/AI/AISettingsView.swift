import SwiftUI

/// A lightweight settings view for configuring the AI connection.  Designed to be presented
/// inside the app's Preferences window or as a standalone sheet.
struct AISettingsView: View {
    @Bindable private var config = AIConfig.shared
    @State private var revealKey = false

    var body: some View {
        Form {
            Section("API Connection") {
                TextField("Base URL", text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .help("Root URL of the OpenAI-compatible service, e.g. https://api.openai.com/v1")
                HStack {
                    if revealKey {
                        TextField("API Key", text: $config.apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $config.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { revealKey.toggle() } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealKey ? "Hide API Key" : "Show API Key")
                }
                TextField("Model", text: $config.model)
                    .textFieldStyle(.roundedBorder)
                    .help("Model identifier, e.g. gpt-4o")
            }
            Section {
                LabeledContent("Endpoint") {
                    Text(config.chatCompletionsURL?.absoluteString ?? "Invalid URL")
                        .foregroundStyle(config.chatCompletionsURL == nil ? .red : .secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Resolved Endpoint")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
    }
}

@MainActor
final class AISettingsWindow {
    static let shared = AISettingsWindow()
    private let panel = FloatingPanelController(name: "aiSettings")

    private init() {}

    func show() {
        panel.show(title: "AI Settings", content: AISettingsView())
    }

    func close() {
        panel.close()
    }
}

import SwiftUI

/// A compact prompt bar for sending natural-language instructions to the AI assistant.
/// Shown at the bottom of the canvas area when `EditorSession.showsAIChat` is true.
struct AIChatPanel: View {
    let session: EditorSession
    @State private var prompt = ""
    @State private var reply = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !reply.isEmpty {
                Text(reply)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                TextField("Tell the AI what to do…", text: $prompt)
                    .textFieldStyle(.plain)
                    .onSubmit { send() }
                    .disabled(isSending)
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Send (Return)")
                }
                Button { AISettingsWindow.shared.show() } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("AI Settings…")
                Button { session.showsAIChat = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close AI Assistant")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
        .frame(maxWidth: 600)
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isSending else { return }
        error = nil
        reply = ""
        isSending = true
        let dispatcher = AIAgentDispatcher(session: session)
        let service = AIService(dispatcher: dispatcher)
        Task {
            do {
                let result = try await service.send(prompt: text)
                reply = result
                prompt = ""
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }
}

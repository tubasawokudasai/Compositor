import Foundation

/// Persistent settings for the OpenAI-compatible API connection. Values are stored in
/// `UserDefaults` under the `"ai."` prefix, following the same pattern as `ToolDefaults`.
/// The API key is kept in the standard defaults for simplicity; a production deployment
/// could move it to the Keychain.
@Observable
final class AIConfig {
    static let shared = AIConfig()

    private static let prefix = "ai."
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    // MARK: - Stored properties

    /// Root URL of the OpenAI-compatible service (e.g. `https://api.openai.com/v1`).
    var baseURL: String {
        didSet { Self.setString(baseURL, "baseURL") }
    }

    /// Bearer token sent in the `Authorization` header.
    var apiKey: String {
        didSet { Self.setString(apiKey, "apiKey") }
    }

    /// Model identifier passed in the chat completion request body.
    var model: String {
        didSet { Self.setString(model, "model") }
    }

    // MARK: - Init

    private init() {
        self.baseURL = Self.string("baseURL", "https://api.openai.com/v1")
        self.apiKey  = Self.string("apiKey", "")
        self.model   = Self.string("model", "gpt-4o")
    }

    // MARK: - Derived

    /// Whether the minimum configuration (a non-empty key) is present.
    var isConfigured: Bool { !apiKey.isEmpty }

    /// Full endpoint URL for `POST /chat/completions`, with any trailing slashes on the
    /// base URL cleaned up.
    var chatCompletionsURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if trimmed.hasSuffix("/v1") || trimmed.contains("/v1/") {
            return URL(string: trimmed + "/chat/completions")
        } else {
            return URL(string: trimmed + "/v1/chat/completions") ?? URL(string: trimmed + "/chat/completions")
        }
    }

    /// Full endpoint URL for `POST /images/edits`, with any trailing slashes on the
    /// base URL cleaned up.
    var imageEditsURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if trimmed.hasSuffix("/v1") || trimmed.contains("/v1/") {
            return URL(string: trimmed + "/images/edits")
        } else {
            return URL(string: trimmed + "/v1/images/edits") ?? URL(string: trimmed + "/images/edits")
        }
    }

    // MARK: - UserDefaults helpers (mirrors ToolDefaults)

    private static func string(_ key: String, _ fallback: String) -> String {
        guard !isTesting else { return fallback }
        return UserDefaults.standard.string(forKey: prefix + key) ?? fallback
    }

    private static func setString(_ value: String, _ key: String) {
        guard !isTesting else { return }
        UserDefaults.standard.set(value, forKey: prefix + key)
    }
}

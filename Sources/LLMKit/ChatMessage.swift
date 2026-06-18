import Foundation

/// A single turn in a chat conversation handed to a ``ModelAdapter``.
///
/// The canonical, provider-neutral message shape. Each adapter translates this
/// into its provider's wire format (OpenAI-style `role`/`content`, Gemini's
/// `contents`/`parts`, Anthropic's top-level `system` + `messages`, etc.).
public struct ChatMessage: Sendable, Codable, Equatable {
    /// The author of a ``ChatMessage``.
    public enum Role: String, Sendable, Codable, Equatable, CaseIterable {
        case system
        case user
        case assistant
    }

    /// Who authored the message.
    public let role: Role
    /// The message text.
    public let content: String

    /// Creates a chat message.
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public extension ChatMessage {
    /// Convenience for a `.system` message.
    static func system(_ content: String) -> ChatMessage {
        .init(role: .system, content: content)
    }

    /// Convenience for a `.user` message.
    static func user(_ content: String) -> ChatMessage {
        .init(role: .user, content: content)
    }

    /// Convenience for an `.assistant` message.
    static func assistant(_ content: String) -> ChatMessage {
        .init(role: .assistant, content: content)
    }
}

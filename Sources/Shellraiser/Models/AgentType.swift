import Foundation

/// Supported agent runtimes that can back a surface session.
enum AgentType: String, Codable, CaseIterable {
    case claudeCode
    case codex

    /// Human-readable display name for UI labels.
    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    /// Returns command and arguments used to resume an existing session.
    func resumeCommand(sessionId: String) -> (command: String, arguments: [String])? {
        guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        switch self {
        case .claudeCode:
            return ("claude", ["--resume", sessionId])
        case .codex:
            return ("codex", ["resume", sessionId])
        }
    }
}

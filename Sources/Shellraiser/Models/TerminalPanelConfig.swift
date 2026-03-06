import Foundation

/// Configuration required for terminal-backed surfaces.
struct TerminalPanelConfig: Codable, Equatable {
    var workingDirectory: String
    var shell: String
    var environment: [String: String]

    /// Builds a default terminal configuration for local sessions.
    static func `default`() -> TerminalPanelConfig {
        TerminalPanelConfig(
            workingDirectory: NSHomeDirectory(),
            shell: "/bin/zsh",
            environment: [:]
        )
    }
}

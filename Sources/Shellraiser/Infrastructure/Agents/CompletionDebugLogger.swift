import Foundation

/// Shared debug logging helper for completion-queue diagnostics.
enum CompletionDebugLogger {
    /// Returns whether completion debug logging is enabled via environment.
    static var isEnabled: Bool {
        let rawValue = ProcessInfo.processInfo.environment["SHELLRAISER_DEBUG_COMPLETIONS"] ?? ""
        return ["1", "true", "yes", "on"].contains(rawValue.lowercased())
    }

    /// Emits a prefixed log line when completion debugging is enabled.
    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        NSLog("[ShellraiserCompletion] \(message())")
    }
}

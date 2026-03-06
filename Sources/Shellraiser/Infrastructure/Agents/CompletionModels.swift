import Foundation

/// Visual emphasis level for pane-level queued completion highlighting.
enum CompletionPaneHighlightState {
    case none
    case recentHold
    case recentFade
    case queued
    case current
}

/// Resolved queued completion target used for jump/focus actions.
struct PendingCompletionTarget {
    let workspaceId: UUID
    let paneId: UUID
    let surface: SurfaceModel
    let sequence: Int
}

/// Parsed completion event emitted by managed Claude/Codex wrappers.
struct AgentCompletionEvent {
    let timestamp: Date
    let agentType: AgentType
    let surfaceId: UUID
    let payload: String

    /// Decodes a tab-delimited completion event log line.
    static func parse(_ line: String) -> AgentCompletionEvent? {
        let components = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard components.count >= 4 else { return nil }
        guard let timestamp = Self.timestampFormatter.date(from: String(components[0])) else { return nil }
        guard let agentType = AgentType(rawValue: String(components[1])) else { return nil }
        guard let surfaceId = UUID(uuidString: String(components[2])) else { return nil }

        let payloadData = Data(base64Encoded: String(components[3])) ?? Data()
        let payload = String(decoding: payloadData, as: UTF8.self)

        return AgentCompletionEvent(
            timestamp: timestamp,
            agentType: agentType,
            surfaceId: surfaceId,
            payload: payload
        )
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

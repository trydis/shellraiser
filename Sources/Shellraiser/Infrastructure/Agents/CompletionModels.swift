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

/// Phase emitted by managed Claude/Codex wrappers for one agent turn.
enum AgentActivityPhase: String {
    case started
    case completed
    case session
    case exited
}

/// Parsed activity event emitted by managed Claude/Codex wrappers.
struct AgentActivityEvent {
    let timestamp: Date
    let agentType: AgentType
    let surfaceId: UUID
    let phase: AgentActivityPhase
    let payload: String

    /// Decodes a tab-delimited activity event log line.
    static func parse(_ line: String) -> AgentActivityEvent? {
        let components = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard components.count >= 5 else { return nil }
        guard let timestamp = Self.timestampFormatter.date(from: String(components[0])) else { return nil }
        guard let agentType = AgentType(rawValue: String(components[1])) else { return nil }
        guard let surfaceId = UUID(uuidString: String(components[2])) else { return nil }
        guard let phase = AgentActivityPhase(rawValue: String(components[3])) else { return nil }
        let payloadColumn = String(components[4])
        let payloadData = Data(base64Encoded: payloadColumn) ?? Data()
        let payload = String(decoding: payloadData, as: UTF8.self)

        return AgentActivityEvent(
            timestamp: timestamp,
            agentType: agentType,
            surfaceId: surfaceId,
            phase: phase,
            payload: payload
        )
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

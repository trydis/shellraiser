import Foundation
import SQLite3

/// Session identity needed to resolve a one-line "what is this agent doing" summary.
struct SessionSummaryRequest: Equatable {
    let agentType: AgentType
    let sessionId: String
    /// Claude Code only — persisted directly on `SurfaceModel`; empty for other agents.
    let transcriptPath: String
}

/// Resolves a short last-activity summary from an agent's on-disk transcript or session store.
///
/// Used by Agent HQ to show *what* an agent is doing, not merely that it is busy. All reads are
/// bounded — transcripts can reach many MB, so this never loads a whole file — and happen off the
/// main actor. Failures (missing file, unparsable line, foreign store unavailable) degrade to a
/// `nil` summary rather than surfacing an error row.
actor SessionSummaryService {
    /// Maximum trailing byte window read from a transcript file.
    private static let tailWindowByteCount = 200_000

    private let fileManager: FileManager
    private let codexSessionsRootURL: URL
    private let copilotSessionStoreURL: URL

    private var cache: [UUID: String] = [:]
    private var inFlightSurfaceIds: Set<UUID> = []
    /// Cache of resolved Codex rollout file paths by session id, avoiding repeated tree walks.
    private var codexRolloutPathBySessionId: [String: URL] = [:]

    /// Creates a summary service rooted at the real Codex/Copilot home directories by default.
    init(
        fileManager: FileManager = .default,
        codexSessionsRootURL: URL? = nil,
        copilotHomeURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        self.codexSessionsRootURL = codexSessionsRootURL
            ?? homeDirectoryURL.appendingPathComponent(".codex/sessions", isDirectory: true)
        self.copilotSessionStoreURL = (
            copilotHomeURL ?? homeDirectoryURL.appendingPathComponent(".copilot", isDirectory: true)
        ).appendingPathComponent("session-store.db")
    }

    /// Returns the cached summary for a surface without triggering a fresh read.
    func cachedSummary(surfaceId: UUID) -> String? {
        cache[surfaceId]
    }

    /// Resolves and caches the last-activity summary for a surface, single-flight per surface.
    ///
    /// Returns the freshly resolved summary, or the previously cached value when a refresh is
    /// already in flight for this surface or the fresh read comes back empty.
    @discardableResult
    func refreshSummary(surfaceId: UUID, request: SessionSummaryRequest) async -> String? {
        guard !inFlightSurfaceIds.contains(surfaceId) else {
            return cache[surfaceId]
        }

        let hasSessionId = !request.sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTranscriptPath = !request.transcriptPath.isEmpty
        guard hasSessionId || hasTranscriptPath else { return nil }

        inFlightSurfaceIds.insert(surfaceId)
        defer { inFlightSurfaceIds.remove(surfaceId) }

        guard let summary = computeSummary(for: request) else {
            return cache[surfaceId]
        }

        cache[surfaceId] = summary
        return summary
    }

    /// Removes a cached summary, e.g. when the owning surface closes.
    func clearCache(surfaceId: UUID) {
        cache.removeValue(forKey: surfaceId)
    }

    // MARK: - Per-agent resolution

    /// Dispatches to the agent-specific summary reader.
    private func computeSummary(for request: SessionSummaryRequest) -> String? {
        switch request.agentType {
        case .claudeCode:
            return claudeSummary(transcriptPath: request.transcriptPath)
        case .codex:
            return codexSummary(sessionId: request.sessionId)
        case .copilot:
            return copilotSummary(sessionId: request.sessionId)
        }
    }

    /// Reads the last assistant text block from a Claude Code JSONL transcript.
    private func claudeSummary(transcriptPath: String) -> String? {
        guard !transcriptPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: transcriptPath)
        guard let lines = tailLines(of: url) else { return nil }

        for line in lines.reversed() {
            guard let object = jsonObject(from: line),
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else {
                continue
            }

            if let text = lastTextBlock(in: content) {
                return oneLine(text)
            }

            if let toolName = lastToolUseName(in: content) {
                return oneLine("Running \(toolName)…")
            }
        }

        return nil
    }

    /// Returns the final `"type": "text"` block's text from a Claude content array, if any.
    private func lastTextBlock(in content: [[String: Any]]) -> String? {
        for block in content.reversed() {
            if block["type"] as? String == "text",
               let text = block["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    /// Returns the final `"type": "tool_use"` block's tool name from a Claude content array, if any.
    private func lastToolUseName(in content: [[String: Any]]) -> String? {
        for block in content.reversed() {
            if block["type"] as? String == "tool_use",
               let name = block["name"] as? String,
               !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// Reads the last `task_complete` agent message from a Codex rollout JSONL file.
    private func codexSummary(sessionId: String) -> String? {
        guard !sessionId.isEmpty, let rolloutURL = resolveCodexRolloutURL(sessionId: sessionId) else {
            return nil
        }
        guard let lines = tailLines(of: rolloutURL) else { return nil }

        for line in lines.reversed() {
            guard let object = jsonObject(from: line),
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "task_complete",
                  let message = payload["last_agent_message"] as? String,
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            return oneLine(message)
        }

        return nil
    }

    /// Locates the Codex rollout file for a session id, caching the resolved path.
    private func resolveCodexRolloutURL(sessionId: String) -> URL? {
        if let cached = codexRolloutPathBySessionId[sessionId] {
            return cached
        }

        guard let enumerator = fileManager.enumerator(
            at: codexSessionsRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let suffix = "-\(sessionId).jsonl"
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent.hasSuffix(suffix) {
            codexRolloutPathBySessionId[sessionId] = fileURL
            return fileURL
        }

        return nil
    }

    /// Reads the last assistant response for a session from Copilot's `session-store.db`,
    /// opened read-only — this store is owned by a live Copilot CLI process and is never written
    /// to by Shellraiser.
    private func copilotSummary(sessionId: String) -> String? {
        guard !sessionId.isEmpty, fileManager.fileExists(atPath: copilotSessionStoreURL.path) else {
            return nil
        }

        var db: OpaquePointer?
        let uri = "file:\(copilotSessionStoreURL.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let database = db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(database) }

        if let response = queryLastAssistantResponse(database: database, sessionId: sessionId) {
            return oneLine(response)
        }

        return queryLastSessionSummary(database: database, sessionId: sessionId).map(oneLine)
    }

    /// Queries the most recent `turns.assistant_response` for a session id.
    private func queryLastAssistantResponse(database: OpaquePointer, sessionId: String) -> String? {
        let sql = """
            SELECT assistant_response FROM turns
            WHERE session_id = ? AND assistant_response IS NOT NULL
            ORDER BY turn_index DESC LIMIT 1;
            """
        return queryFirstColumnText(database: database, sql: sql, sessionId: sessionId)
    }

    /// Queries `sessions.summary` as a fallback when no turn text is available.
    private func queryLastSessionSummary(database: OpaquePointer, sessionId: String) -> String? {
        let sql = "SELECT summary FROM sessions WHERE id = ? LIMIT 1;"
        return queryFirstColumnText(database: database, sql: sql, sessionId: sessionId)
    }

    /// Executes a single-parameter, single-column text query and returns its first non-empty result.
    private func queryFirstColumnText(database: OpaquePointer, sql: String, sessionId: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, sessionId, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW, let cString = sqlite3_column_text(statement, 0) else {
            return nil
        }

        let text = String(cString: cString)
        return text.isEmpty ? nil : text
    }

    // MARK: - Shared parsing helpers

    /// Reads a bounded trailing byte window from a file and splits it into complete lines.
    ///
    /// Drops a possibly-truncated leading partial line since transcripts can reach many MB and
    /// this service must never read a whole file into memory.
    private func tailLines(of url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd() else { return nil }
        let windowSize = UInt64(Self.tailWindowByteCount)
        let readStart = fileSize > windowSize ? fileSize - windowSize : 0
        try? handle.seek(toOffset: readStart)

        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        // Drop a partial leading line unless the window began at the true start of the file.
        if readStart > 0, !lines.isEmpty {
            lines.removeFirst()
        }
        return lines
    }

    /// Parses one JSONL line into a loosely-typed dictionary, ignoring malformed lines.
    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Collapses newlines/whitespace so summaries render on a single UI line.
    private func oneLine(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

import Foundation
import SQLite3
import XCTest
@testable import Shellraiser

/// Covers per-agent transcript/session-store parsing and caching behavior.
final class SessionSummaryServiceTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionSummaryServiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
        super.tearDown()
    }

    // MARK: - Claude Code

    /// Verifies the last assistant text block is extracted, skipping interleaved non-message records.
    func testClaudeSummaryReturnsLastAssistantTextBlock() async {
        let transcriptURL = tempDirectoryURL.appendingPathComponent("transcript.jsonl")
        let lines = [
            #"{"type":"mode","mode":"default"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Working on it."}]}}"#,
            #"{"type":"permission-mode","permissionMode":"default"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Done!\nAll tests pass."}]}}"#
        ]
        try? lines.joined(separator: "\n").write(to: transcriptURL, atomically: true, encoding: .utf8)

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(agentType: .claudeCode, sessionId: "", transcriptPath: transcriptURL.path)
        )

        XCTAssertEqual(summary, "Done! All tests pass.")
    }

    /// Verifies a trailing tool_use-only message falls back to a "Running <tool>…" summary.
    func testClaudeSummaryFallsBackToToolUseWhenNoTrailingText() async {
        let transcriptURL = tempDirectoryURL.appendingPathComponent("transcript.jsonl")
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Let me check."}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}"#
        ]
        try? lines.joined(separator: "\n").write(to: transcriptURL, atomically: true, encoding: .utf8)

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(agentType: .claudeCode, sessionId: "", transcriptPath: transcriptURL.path)
        )

        XCTAssertEqual(summary, "Running Bash…")
    }

    /// Verifies a missing transcript file degrades to nil rather than throwing or crashing.
    func testClaudeSummaryReturnsNilForMissingTranscript() async {
        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(
                agentType: .claudeCode,
                sessionId: "",
                transcriptPath: tempDirectoryURL.appendingPathComponent("missing.jsonl").path
            )
        )

        XCTAssertNil(summary)
    }

    // MARK: - Codex

    /// Verifies the rollout file is located by session id under nested date directories and the
    /// last task_complete message is returned.
    func testCodexSummaryLocatesRolloutBySessionIdAndReturnsLastAgentMessage() async {
        let sessionId = "019fc7c0-f726-7392-ae78-4f2ee086a64c"
        let rolloutDirectory = tempDirectoryURL
            .appendingPathComponent("codex/sessions/2026/08/03", isDirectory: true)
        try? FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)
        let rolloutURL = rolloutDirectory.appendingPathComponent("rollout-2026-08-03T15-12-20-\(sessionId).jsonl")

        let lines = [
            #"{"type":"session_meta","payload":{"session_id":"\#(sessionId)"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"First pass."}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Clean. 150 tests pass."}}"#
        ]
        try? lines.joined(separator: "\n").write(to: rolloutURL, atomically: true, encoding: .utf8)

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex/sessions"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(agentType: .codex, sessionId: sessionId, transcriptPath: "")
        )

        XCTAssertEqual(summary, "Clean. 150 tests pass.")
    }

    /// Verifies a rollout file containing only session_meta (no completed turn yet) yields nil.
    func testCodexSummaryReturnsNilWhenNoTaskCompleteEventExists() async {
        let sessionId = "session-meta-only"
        let rolloutDirectory = tempDirectoryURL
            .appendingPathComponent("codex/sessions/2026/08/03", isDirectory: true)
        try? FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)
        let rolloutURL = rolloutDirectory.appendingPathComponent("rollout-2026-08-03T15-12-20-\(sessionId).jsonl")
        try? #"{"type":"session_meta","payload":{"session_id":"\#(sessionId)"}}"#
            .write(to: rolloutURL, atomically: true, encoding: .utf8)

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex/sessions"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(agentType: .codex, sessionId: sessionId, transcriptPath: "")
        )

        XCTAssertNil(summary)
    }

    /// Verifies an unknown session id (no matching rollout file anywhere) yields nil.
    func testCodexSummaryReturnsNilForUnknownSessionId() async {
        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex/sessions"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(agentType: .codex, sessionId: "does-not-exist", transcriptPath: "")
        )

        XCTAssertNil(summary)
    }

    // MARK: - Copilot

    /// Verifies the most recent turn's assistant_response is preferred over the session summary.
    func testCopilotSummaryPrefersLatestAssistantResponseOverSessionSummary() async throws {
        let copilotHomeURL = tempDirectoryURL.appendingPathComponent("copilot", isDirectory: true)
        try FileManager.default.createDirectory(at: copilotHomeURL, withIntermediateDirectories: true)
        let sessionId = "copilot-session-1"
        try makeCopilotSessionStore(
            at: copilotHomeURL.appendingPathComponent("session-store.db"),
            sessionId: sessionId,
            sessionSummary: "Fallback summary",
            turns: [(0, "Old response"), (1, "Latest response")]
        )

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: copilotHomeURL
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(agentType: .copilot, sessionId: sessionId, transcriptPath: "")
        )

        XCTAssertEqual(summary, "Latest response")
    }

    /// Verifies sessions.summary is used when no turn has an assistant_response yet.
    func testCopilotSummaryFallsBackToSessionSummaryWhenNoTurnResponse() async throws {
        let copilotHomeURL = tempDirectoryURL.appendingPathComponent("copilot", isDirectory: true)
        try FileManager.default.createDirectory(at: copilotHomeURL, withIntermediateDirectories: true)
        let sessionId = "copilot-session-2"
        try makeCopilotSessionStore(
            at: copilotHomeURL.appendingPathComponent("session-store.db"),
            sessionId: sessionId,
            sessionSummary: "Session just started",
            turns: []
        )

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: copilotHomeURL
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(agentType: .copilot, sessionId: sessionId, transcriptPath: "")
        )

        XCTAssertEqual(summary, "Session just started")
    }

    /// Verifies a missing session-store.db degrades to nil rather than throwing.
    func testCopilotSummaryReturnsNilWhenStoreIsMissing() async {
        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot-missing")
        )
        let summary = await service.refreshSummary(
            surfaceId: UUID(),
            request: SessionSummaryRequest(agentType: .copilot, sessionId: "any-session", transcriptPath: "")
        )

        XCTAssertNil(summary)
    }

    // MARK: - Caching

    /// Verifies a resolved summary is cached and clearCache removes it.
    func testCacheStoresResolvedSummaryUntilCleared() async {
        let transcriptURL = tempDirectoryURL.appendingPathComponent("transcript.jsonl")
        try? #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello."}]}}"#
            .write(to: transcriptURL, atomically: true, encoding: .utf8)

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let surfaceId = UUID()

        let initialCached = await service.cachedSummary(surfaceId: surfaceId)
        XCTAssertNil(initialCached)

        _ = await service.refreshSummary(
            surfaceId: surfaceId,
            request: SessionSummaryRequest(agentType: .claudeCode, sessionId: "", transcriptPath: transcriptURL.path)
        )
        let cachedAfterRefresh = await service.cachedSummary(surfaceId: surfaceId)
        XCTAssertEqual(cachedAfterRefresh, "Hello.")

        await service.clearCache(surfaceId: surfaceId)
        let cachedAfterClear = await service.cachedSummary(surfaceId: surfaceId)
        XCTAssertNil(cachedAfterClear)
    }

    // MARK: - Fixtures

    /// Creates a minimal Copilot `session-store.db` fixture matching the real schema.
    private func makeCopilotSessionStore(
        at url: URL,
        sessionId: String,
        sessionSummary: String,
        turns: [(index: Int, response: String)]
    ) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let database = db else {
            XCTFail("Failed to create test sqlite database")
            return
        }
        defer { sqlite3_close(database) }

        try execute(
            database,
            """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                cwd TEXT,
                repository TEXT,
                host_type TEXT,
                branch TEXT,
                summary TEXT,
                created_at TEXT,
                updated_at TEXT
            );
            """
        )
        try execute(
            database,
            """
            CREATE TABLE turns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                turn_index INTEGER NOT NULL,
                user_message TEXT,
                assistant_response TEXT,
                timestamp TEXT
            );
            """
        )

        let escapedSummary = sessionSummary.replacingOccurrences(of: "'", with: "''")
        try execute(
            database,
            "INSERT INTO sessions (id, summary) VALUES ('\(sessionId)', '\(escapedSummary)');"
        )

        for turn in turns {
            let escapedResponse = turn.response.replacingOccurrences(of: "'", with: "''")
            try execute(
                database,
                """
                INSERT INTO turns (session_id, turn_index, assistant_response)
                VALUES ('\(sessionId)', \(turn.index), '\(escapedResponse)');
                """
            )
        }
    }

    /// Executes a single SQL statement, failing the test on error.
    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(errorMessage)
            XCTFail("SQL execution failed: \(message)")
            return
        }
    }
}

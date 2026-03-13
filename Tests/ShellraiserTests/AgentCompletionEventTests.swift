import XCTest
@testable import Shellraiser

/// Covers parsing behavior for tab-delimited managed-agent activity events.
final class AgentCompletionEventTests: XCTestCase {
    /// Verifies valid log lines decode timestamps, phase, agent type, surface id, and base64 payloads.
    func testParseDecodesValidActivityEvent() {
        let surfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001401")!
        let payload = Data("hello world".utf8).base64EncodedString()
        let line = "2026-03-08T20:00:00Z\tcodex\t\(surfaceId.uuidString)\tcompleted\t\(payload)"

        let event = AgentActivityEvent.parse(line)

        XCTAssertEqual(event?.agentType, .codex)
        XCTAssertEqual(event?.surfaceId, surfaceId)
        XCTAssertEqual(event?.phase, .completed)
        XCTAssertEqual(event?.payload, "hello world")
        XCTAssertEqual(event?.timestamp, ISO8601DateFormatter().date(from: "2026-03-08T20:00:00Z"))
    }

    /// Verifies session-identity events decode their payload and dedicated phase.
    func testParseDecodesSessionIdentityEvent() {
        let surfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001402")!
        let payload = Data("019ce8bb-b369-7693-9be0-664a228e4e24".utf8).base64EncodedString()
        let line = "2026-03-08T20:05:00Z\tclaudeCode\t\(surfaceId.uuidString)\tsession\t\(payload)"

        let event = AgentActivityEvent.parse(line)

        XCTAssertEqual(event?.agentType, .claudeCode)
        XCTAssertEqual(event?.surfaceId, surfaceId)
        XCTAssertEqual(event?.phase, .session)
        XCTAssertEqual(event?.payload, "019ce8bb-b369-7693-9be0-664a228e4e24")
    }

    /// Verifies exit lifecycle events decode without requiring a payload body.
    func testParseDecodesExitedEvent() {
        let surfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001403")!
        let line = "2026-03-08T20:06:00Z\tcodex\t\(surfaceId.uuidString)\texited\t"

        let event = AgentActivityEvent.parse(line)

        XCTAssertEqual(event?.agentType, .codex)
        XCTAssertEqual(event?.surfaceId, surfaceId)
        XCTAssertEqual(event?.phase, .exited)
        XCTAssertEqual(event?.payload, "")
    }

    /// Verifies malformed lines are rejected instead of partially parsed.
    func testParseRejectsMalformedActivityEventLines() {
        XCTAssertNil(AgentActivityEvent.parse(""))
        XCTAssertNil(AgentActivityEvent.parse("2026-03-08T20:00:00Z\tcodex"))
        XCTAssertNil(AgentActivityEvent.parse("invalid-date\tcodex\t00000000-0000-0000-0000-000000001401\tcompleted\t"))
        XCTAssertNil(AgentActivityEvent.parse("2026-03-08T20:00:00Z\tunknown\t00000000-0000-0000-0000-000000001401\tcompleted\t"))
        XCTAssertNil(AgentActivityEvent.parse("2026-03-08T20:00:00Z\tcodex\tnot-a-uuid\tcompleted\t"))
        XCTAssertNil(AgentActivityEvent.parse("2026-03-08T20:00:00Z\tcodex\t00000000-0000-0000-0000-000000001401\tunknown\t"))
    }
}

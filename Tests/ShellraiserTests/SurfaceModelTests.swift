import XCTest
@testable import Shellraiser

/// Covers backward-compatible surface encoding and decoding behavior.
final class SurfaceModelTests: XCTestCase {
    /// Verifies legacy payloads derive queued-completion state from unread idle notifications.
    func testLegacyDecodingSuppliesDefaultCompletionMetadata() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000401",
          "title": "Legacy Surface",
          "sessionId": "legacy-session",
          "hasUnreadIdleNotification": true
        }
        """.data(using: .utf8)!

        let decodedSurface = try JSONDecoder().decode(SurfaceModel.self, from: json)

        XCTAssertEqual(decodedSurface.id, UUID(uuidString: "00000000-0000-0000-0000-000000000401"))
        XCTAssertEqual(decodedSurface.title, "Legacy Surface")
        XCTAssertEqual(decodedSurface.agentType, .claudeCode)
        XCTAssertEqual(decodedSurface.sessionId, "legacy-session")
        XCTAssertEqual(decodedSurface.transcriptPath, "")
        XCTAssertFalse(decodedSurface.shouldResumeSession)
        XCTAssertTrue(decodedSurface.hasUnreadIdleNotification)
        XCTAssertTrue(decodedSurface.hasPendingCompletion)
        XCTAssertFalse(decodedSurface.isIdle)
        XCTAssertNil(decodedSurface.pendingCompletionSequence)
        XCTAssertNil(decodedSurface.lastCompletionAt)
        XCTAssertEqual(decodedSurface.terminalConfig.shell, "/bin/zsh")
        XCTAssertEqual(decodedSurface.terminalConfig.environment, [:])
    }
}

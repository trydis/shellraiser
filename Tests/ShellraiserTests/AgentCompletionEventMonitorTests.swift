import Foundation
import XCTest
@testable import Shellraiser

/// Covers file-tail behavior for managed-agent activity event monitoring.
final class AgentCompletionEventMonitorTests: XCTestCase {
    /// Verifies the monitor emits appended activity events for valid log lines.
    func testMonitorEmitsEventForAppendedLine() throws {
        let logURL = try makeLogFile()
        let expectation = expectation(description: "Monitor emits appended activity event")
        let expectedSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001601")!
        let expectedTimestamp = ISO8601DateFormatter().date(from: "2026-03-08T20:30:00Z")!
        let monitor = AgentCompletionEventMonitor(logURL: logURL)

        monitor.onEvent = { event in
            XCTAssertEqual(event.agentType, .codex)
            XCTAssertEqual(event.surfaceId, expectedSurfaceId)
            XCTAssertEqual(event.phase, .completed)
            XCTAssertEqual(event.payload, "hello")
            XCTAssertEqual(event.timestamp, expectedTimestamp)
            expectation.fulfill()
        }

        appendLine(
            "2026-03-08T20:30:00Z\tcodex\t\(expectedSurfaceId.uuidString)\tcompleted\t\(Data("hello".utf8).base64EncodedString())",
            to: logURL
        )

        wait(for: [expectation], timeout: 1.0)
        withExtendedLifetime(monitor) {}
    }

    /// Verifies historical file contents are ignored and malformed appended lines are skipped.
    func testMonitorIgnoresHistoricalAndMalformedLines() throws {
        let logURL = try makeLogFile(
            initialContents: "2026-03-08T20:00:00Z\tcodex\t00000000-0000-0000-0000-000000001699\tcompleted\t\(Data("old".utf8).base64EncodedString())\n"
        )
        let historicalExpectation = expectation(description: "Historical event ignored")
        historicalExpectation.isInverted = true
        let appendedExpectation = expectation(description: "Appended valid event emitted")
        let expectedSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001602")!
        let monitor = AgentCompletionEventMonitor(logURL: logURL)

        monitor.onEvent = { event in
            if event.surfaceId == expectedSurfaceId {
                appendedExpectation.fulfill()
            } else {
                historicalExpectation.fulfill()
            }
        }

        wait(for: [historicalExpectation], timeout: 0.2)
        appendLine("not-a-valid-event", to: logURL)
        appendLine(
            "2026-03-08T20:31:00Z\tclaudeCode\t\(expectedSurfaceId.uuidString)\tstarted\t",
            to: logURL
        )

        wait(for: [appendedExpectation], timeout: 1.0)
        withExtendedLifetime(monitor) {}
    }

    /// Creates a disposable event log file for monitor tests.
    private func makeLogFile(initialContents: String = "") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shellraiser-event-monitor-\(UUID().uuidString).log"
        )
        try Data(initialContents.utf8).write(to: url, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    /// Appends a newline-terminated log line to an existing test file.
    private func appendLine(_ line: String, to url: URL) {
        let handle = try! FileHandle(forWritingTo: url)
        try! handle.seekToEnd()
        handle.write(Data((line + "\n").utf8))
        try! handle.close()
    }
}

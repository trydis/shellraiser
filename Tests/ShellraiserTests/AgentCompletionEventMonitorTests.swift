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

    /// Verifies compaction truncates a fully consumed oversized log and tailing resumes from the reset offset.
    func testMonitorCompactsOversizedLogAndContinuesReading() throws {
        let logURL = try makeLogFile()
        let firstSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001603")!
        let secondSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001604")!
        let firstExpectation = expectation(description: "First event emitted before compaction")
        let secondExpectation = expectation(description: "Second event emitted after compaction")
        let monitor = AgentCompletionEventMonitor(logURL: logURL, compactionThresholdBytes: 1)

        monitor.onEvent = { event in
            switch event.surfaceId {
            case firstSurfaceId:
                firstExpectation.fulfill()
            case secondSurfaceId:
                secondExpectation.fulfill()
            default:
                XCTFail("Unexpected surface id \(event.surfaceId)")
            }
        }

        appendLine(eventLine(surfaceId: firstSurfaceId, payload: "first"), to: logURL)
        wait(for: [firstExpectation], timeout: 1.0)
        XCTAssertTrue(waitForCondition(timeout: 1.0) {
            self.currentFileSize(of: logURL) == 0
        })

        appendLine(eventLine(surfaceId: secondSurfaceId, payload: "second"), to: logURL)
        wait(for: [secondExpectation], timeout: 1.0)
        withExtendedLifetime(monitor) {}
    }

    /// Verifies compaction skips truncation when a new append lands after reading but before the lock is acquired.
    func testMonitorSkipsCompactionWhenNewEventArrivesDuringRaceWindow() throws {
        let logURL = try makeLogFile()
        let firstSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001605")!
        let secondSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001606")!
        let appendExpectation = expectation(description: "Racing append executed")
        let firstExpectation = expectation(description: "First event emitted")
        let secondExpectation = expectation(description: "Racing event emitted")
        let monitor = AgentCompletionEventMonitor(
            logURL: logURL,
            compactionThresholdBytes: 1,
            beforeCompactionAttempt: {
                self.appendLine(self.eventLine(surfaceId: secondSurfaceId, payload: "racing"), to: logURL)
                appendExpectation.fulfill()
            }
        )

        monitor.onEvent = { event in
            switch event.surfaceId {
            case firstSurfaceId:
                firstExpectation.fulfill()
            case secondSurfaceId:
                secondExpectation.fulfill()
            default:
                XCTFail("Unexpected surface id \(event.surfaceId)")
            }
        }

        appendLine(eventLine(surfaceId: firstSurfaceId, payload: "first"), to: logURL)

        wait(for: [appendExpectation, firstExpectation, secondExpectation], timeout: 1.0)
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

    /// Returns a valid completion-event log line for the provided surface and payload.
    private func eventLine(
        surfaceId: UUID,
        payload: String,
        timestamp: String = "2026-03-08T20:32:00Z"
    ) -> String {
        let encodedPayload = Data(payload.utf8).base64EncodedString()
        return "\(timestamp)\tcodex\t\(surfaceId.uuidString)\tcompleted\t\(encodedPayload)"
    }

    /// Appends a newline-terminated log line to an existing test file.
    private func appendLine(_ line: String, to url: URL) {
        let handle = try! FileHandle(forWritingTo: url)
        try! handle.seekToEnd()
        handle.write(Data((line + "\n").utf8))
        try! handle.close()
    }

    /// Returns the current byte size for the supplied log file.
    private func currentFileSize(of url: URL) -> UInt64 {
        let attributes = try! FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as! NSNumber
        return size.uint64Value
    }

    /// Polls until the supplied condition becomes true or the timeout elapses.
    private func waitForCondition(
        timeout: TimeInterval,
        interval: TimeInterval = 0.01,
        condition: @escaping () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }

        return condition()
    }
}

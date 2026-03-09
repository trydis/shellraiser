import AppKit
import XCTest
@testable import Shellraiser

/// Covers AppKit command interpretation decisions for terminal key forwarding.
final class LibghosttySurfaceViewTests: XCTestCase {
    /// Verifies command-interpreted keys are forwarded without a text payload.
    func testFallbackTextPayloadOmitsTextForInterpretedCommands() {
        let payload = LibghosttySurfaceView.fallbackTextPayload(
            interpretedCommand: true,
            characters: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        )

        XCTAssertNil(payload)
    }

    /// Verifies printable keys preserve their text payload when no command selector fired.
    func testFallbackTextPayloadKeepsPrintableCharacters() {
        let payload = LibghosttySurfaceView.fallbackTextPayload(
            interpretedCommand: false,
            characters: "j"
        )

        XCTAssertEqual(payload, "j")
    }

    /// Verifies IME composition state stays active while marked text exists or was active before interpretation.
    func testIsComposingReflectsCurrentAndPreviousMarkedTextState() {
        XCTAssertTrue(LibghosttySurfaceView.isComposing(markedTextLength: 1, markedTextBefore: false))
        XCTAssertTrue(LibghosttySurfaceView.isComposing(markedTextLength: 0, markedTextBefore: true))
        XCTAssertFalse(LibghosttySurfaceView.isComposing(markedTextLength: 0, markedTextBefore: false))
    }
}

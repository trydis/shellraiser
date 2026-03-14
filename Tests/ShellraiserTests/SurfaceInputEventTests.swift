import AppKit
import XCTest
@testable import Shellraiser

/// Covers submit-like input classification used by Codex busy heuristics.
final class SurfaceInputEventTests: XCTestCase {
    /// Verifies Return-like keys are classified as user submissions.
    func testClassifyUserKeyTreatsReturnEnterAndControlMAsSubmit() {
        XCTAssertEqual(
            SurfaceInputEvent.classifyUserKey(keyCode: 36, modifiers: []),
            .userSubmit
        )
        XCTAssertEqual(
            SurfaceInputEvent.classifyUserKey(keyCode: 76, modifiers: []),
            .userSubmit
        )
        XCTAssertEqual(
            SurfaceInputEvent.classifyUserKey(keyCode: 46, modifiers: [.control]),
            .userSubmit
        )
    }

    /// Verifies ambiguous or generic keys remain non-submit input.
    func testClassifyUserKeyLeavesControlJAndPrintableKeysAsInput() {
        XCTAssertEqual(
            SurfaceInputEvent.classifyUserKey(keyCode: 38, modifiers: [.control]),
            .userInput
        )
        XCTAssertEqual(
            SurfaceInputEvent.classifyUserKey(keyCode: 46, modifiers: []),
            .userInput
        )
    }

    /// Verifies scripted text only submits when it ends with a newline.
    func testClassifyScriptedTextRequiresTrailingNewline() {
        XCTAssertEqual(SurfaceInputEvent.classifyScriptedText("codex"), .scriptedInput)
        XCTAssertEqual(SurfaceInputEvent.classifyScriptedText("codex\n"), .scriptedSubmit)
        XCTAssertEqual(SurfaceInputEvent.classifyScriptedText("codex\r"), .scriptedSubmit)
    }

    /// Verifies only Enter-like AppleScript key names are treated as submit.
    func testClassifyScriptedKeyNameRequiresEnterOrReturn() {
        XCTAssertEqual(SurfaceInputEvent.classifyScriptedKeyName("enter"), .scriptedSubmit)
        XCTAssertEqual(SurfaceInputEvent.classifyScriptedKeyName("return"), .scriptedSubmit)
        XCTAssertEqual(SurfaceInputEvent.classifyScriptedKeyName("tab"), .scriptedInput)
    }
}

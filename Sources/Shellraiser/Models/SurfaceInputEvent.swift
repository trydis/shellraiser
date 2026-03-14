import AppKit
import Foundation

/// Categorizes terminal activity into generic input versus likely prompt submission.
enum SurfaceInputEvent: Equatable {
    case userInput
    case userSubmit
    case scriptedInput
    case scriptedSubmit

    /// Returns whether the input should be treated as a prompt submission.
    var isSubmit: Bool {
        switch self {
        case .userSubmit, .scriptedSubmit:
            return true
        case .userInput, .scriptedInput:
            return false
        }
    }

    /// Classifies a keyboard event using the submit-like keys supported by Shellraiser.
    static func classifyUserKey(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> SurfaceInputEvent {
        let relevantModifiers = modifiers.intersection([.shift, .control, .option, .command])

        if keyCode == 36 || keyCode == 76 {
            return .userSubmit
        }

        if keyCode == 46,
           (relevantModifiers == [.control] || relevantModifiers == [.shift, .control]) {
            return .userSubmit
        }

        return .userInput
    }

    /// Classifies scripted text input by whether it ends with a submitted newline.
    static func classifyScriptedText(_ text: String) -> SurfaceInputEvent {
        guard let lastScalar = text.unicodeScalars.last else {
            return .scriptedInput
        }

        if lastScalar == "\n" || lastScalar == "\r" {
            return .scriptedSubmit
        }

        return .scriptedInput
    }

    /// Classifies AppleScript named keys into generic input versus prompt submission.
    static func classifyScriptedKeyName(_ keyName: String) -> SurfaceInputEvent {
        switch keyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "enter", "return":
            return .scriptedSubmit
        default:
            return .scriptedInput
        }
    }
}

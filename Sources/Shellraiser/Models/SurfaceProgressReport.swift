import SwiftUI

/// Progress state reported by a terminal surface via OSC 9;4.
enum SurfaceProgressState: Equatable {
    case set
    case error
    case indeterminate
    case pause

    /// Tint color representing the progress state in UI elements.
    var tintColor: Color {
        switch self {
        case .error: return .red
        case .pause: return .orange
        default: return .accentColor
        }
    }
}

/// Progress report delivered by a terminal surface via OSC 9;4.
struct SurfaceProgressReport: Equatable {
    /// Current progress state.
    let state: SurfaceProgressState
    /// Percentage completion (0–100), or nil when not quantified.
    let progress: UInt8?

    init(state: SurfaceProgressState, progress: UInt8?) {
        self.state = state
        self.progress = progress.map { min($0, 100) }
    }
}

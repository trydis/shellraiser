/// Progress state reported by a terminal surface via OSC 9;4.
enum SurfaceProgressState: Equatable {
    case set
    case error
    case indeterminate
    case pause
}

/// Progress report delivered by a terminal surface via OSC 9;4.
struct SurfaceProgressReport: Equatable {
    /// Current progress state.
    let state: SurfaceProgressState
    /// Percentage completion (0–100), or nil when not quantified.
    let progress: UInt8?
}

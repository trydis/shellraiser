import Combine
import Foundation

/// Observable state model tracking an active in-terminal search session for a single surface.
@MainActor
final class SurfaceSearchState: ObservableObject {
    /// The current search needle text.
    @Published var needle: String

    /// The index of the currently selected match (1-based), or nil when unknown.
    @Published var selected: UInt?

    /// The total number of matches, or nil when unknown.
    @Published var total: UInt?

    /// Creates a new search state with an optional initial needle.
    init(needle: String = "") {
        self.needle = needle
    }
}

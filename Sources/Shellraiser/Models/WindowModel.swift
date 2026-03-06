import Foundation

/// Window-level presentation state that is not persisted.
struct WindowModel: Equatable {
    var selectedWorkspaceId: UUID?
    var isSidebarCollapsed: Bool

    /// Creates default window state.
    static func initial() -> WindowModel {
        WindowModel(selectedWorkspaceId: nil, isSidebarCollapsed: false)
    }
}

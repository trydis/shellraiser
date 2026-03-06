import AppKit
import SwiftUI

/// Renderer for split pane nodes with a draggable divider.
struct PaneSplitView: View {
    let workspaceId: UUID
    let split: PaneSplitModel
    @ObservedObject var manager: WorkspaceManager

    @State private var dragRatio: Double?
    @State private var dragStartRatio: Double?
    private let dividerThickness: CGFloat = 10

    /// Terminal chrome styling shared by split dividers.
    private var chromeStyle: GhosttyRuntime.ChromeStyle {
        GhosttyRuntime.shared.chromeStyle()
    }

    /// Active ratio used while dragging and while idle.
    private var activeRatio: Double {
        let value = dragRatio ?? split.ratio
        return min(0.9, max(0.1, value))
    }

    var body: some View {
        GeometryReader { geometry in
            if split.orientation == .horizontal {
                horizontalContent(in: geometry.size)
            } else {
                verticalContent(in: geometry.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Builds a horizontal split layout.
    private func horizontalContent(in size: CGSize) -> some View {
        let usableWidth = max(0, size.width - dividerThickness)
        let firstWidth = usableWidth * activeRatio
        let secondWidth = max(0, usableWidth - firstWidth)

        return HStack(spacing: 0) {
            PaneNodeView(workspaceId: workspaceId, node: split.first, manager: manager)
                .frame(width: firstWidth)
                .frame(maxHeight: .infinity)

            SplitDivider(chromeStyle: chromeStyle, isHorizontal: true)
                .frame(width: dividerThickness)
                .gesture(dividerDragGesture(total: usableWidth, horizontal: true))

            PaneNodeView(workspaceId: workspaceId, node: split.second, manager: manager)
                .frame(width: secondWidth)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Builds a vertical split layout.
    private func verticalContent(in size: CGSize) -> some View {
        let usableHeight = max(0, size.height - dividerThickness)
        let firstHeight = usableHeight * activeRatio
        let secondHeight = max(0, usableHeight - firstHeight)

        return VStack(spacing: 0) {
            PaneNodeView(workspaceId: workspaceId, node: split.first, manager: manager)
                .frame(height: firstHeight)
                .frame(maxWidth: .infinity)

            SplitDivider(chromeStyle: chromeStyle, isHorizontal: false)
                .frame(height: dividerThickness)
                .gesture(dividerDragGesture(total: usableHeight, horizontal: false))

            PaneNodeView(workspaceId: workspaceId, node: split.second, manager: manager)
                .frame(height: secondHeight)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Creates the drag gesture that updates a split ratio.
    private func dividerDragGesture(total: CGFloat, horizontal: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                applyDrag(translation: value.translation, total: total, horizontal: horizontal)
            }
            .onEnded { value in
                applyDrag(translation: value.translation, total: total, horizontal: horizontal)
                if let dragRatio {
                    manager.updateSplitRatio(workspaceId: workspaceId, paneId: split.id, ratio: dragRatio)
                }
                dragRatio = nil
                dragStartRatio = nil
            }
    }

    /// Applies a drag translation to the current split ratio.
    private func applyDrag(translation: CGSize, total: CGFloat, horizontal: Bool) {
        guard total > 0 else { return }

        let startRatio = dragStartRatio ?? split.ratio
        if dragStartRatio == nil {
            dragStartRatio = startRatio
        }

        let axisTranslation = horizontal ? translation.width : translation.height
        let ratio = min(0.9, max(0.1, startRatio + Double(axisTranslation / total)))

        dragRatio = ratio
    }
}

/// Visible split divider handle.
struct SplitDivider: View {
    let chromeStyle: GhosttyRuntime.ChromeStyle
    let isHorizontal: Bool
    @State private var isHovered = false

    /// Mouse cursor shown while the divider can be dragged.
    private var cursor: NSCursor {
        isHorizontal ? .resizeLeftRight : .resizeUpDown
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color(nsColor: chromeStyle.splitDividerColor).opacity(0.85))
                .frame(width: isHorizontal ? 4 : 52, height: isHorizontal ? 52 : 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .strokeBorder(AppTheme.stroke, lineWidth: 1)
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                cursor.push()
            } else if isHovered {
                NSCursor.pop()
            }
            isHovered = hovering
        }
    }
}

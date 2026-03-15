import SwiftUI

/// Full-width search bar that appears at the top of an active terminal pane.
struct TerminalSearchOverlay: View {
    /// Live search state shared with the runtime.
    @ObservedObject var searchState: SurfaceSearchState

    /// Called when the user requests the next match.
    let onNavigateNext: () -> Void

    /// Called when the user requests the previous match.
    let onNavigatePrevious: () -> Void

    /// Called when the overlay should be dismissed.
    let onClose: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("Search", text: $searchState.needle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused($isTextFieldFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            onNavigatePrevious()
                        } else {
                            onNavigateNext()
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onClose()
                        return .handled
                    }

                if let selected = searchState.selected, let total = searchState.total {
                    Text("\(selected) of \(total)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                        .animation(nil, value: total)
                }
            }
            .padding(.leading, 12)

            Spacer()

            HStack(spacing: 1) {
                SearchNavButton(systemImage: "chevron.up", action: onNavigatePrevious)
                    .help("Previous match")
                SearchNavButton(systemImage: "chevron.down", action: onNavigateNext)
                    .help("Next match")

                Rectangle()
                    .fill(AppTheme.stroke)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 5)

                SearchNavButton(systemImage: "xmark", action: onClose)
                    .help("Close search")
            }
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Color(nsColor: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.20, alpha: 1.0)))
        .clipShape(TopRoundedShape(radius: 10))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.stroke)
                .frame(height: 1)
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

/// Small icon button used for search navigation and close actions.
private struct SearchNavButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(SearchNavButtonStyle())
    }
}

private struct SearchNavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.textPrimary.opacity(configuration.isPressed ? 0.45 : 0.72))
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0))
            )
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

/// Rectangle with rounded top corners and square bottom corners.
private struct TopRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(270),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

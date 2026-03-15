import SwiftUI

/// Compact search panel that floats over the top-right corner of the active terminal pane.
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
            // Search icon + text field + match count
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("Search", text: $searchState.needle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(minWidth: 150)
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
            .padding(.leading, 10)

            // Separator + navigation + close buttons
            HStack(spacing: 1) {
                Rectangle()
                    .fill(AppTheme.stroke)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 6)

                SearchNavButton(systemImage: "chevron.up", action: onNavigatePrevious)
                    .help("Previous match")
                SearchNavButton(systemImage: "chevron.down", action: onNavigateNext)
                    .help("Next match")

                Rectangle()
                    .fill(AppTheme.stroke)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 4)

                SearchNavButton(systemImage: "xmark", action: onClose)
                    .help("Close search")
            }
            .padding(.trailing, 6)
        }
        .frame(height: 30)
        .background(
            Color(nsColor: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 0.97))
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(AppTheme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
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
            .foregroundStyle(AppTheme.textPrimary.opacity(configuration.isPressed ? 0.40 : 0.70))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0))
            )
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

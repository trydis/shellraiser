import SwiftUI

/// Floating search bar rendered over an active terminal pane.
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
        HStack(spacing: 8) {
            TextField("Find…", text: $searchState.needle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(minWidth: 160)
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
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(minWidth: 60, alignment: .trailing)
                    .animation(nil, value: total)
            }

            Divider()
                .frame(height: 14)
                .opacity(0.4)

            Button(action: onNavigatePrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(ChromeIconButtonStyle())
            .help("Previous match")

            Button(action: onNavigateNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(ChromeIconButtonStyle())
            .help("Next match")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(ChromeIconButtonStyle())
            .help("Close search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .chromeCard()
        .padding(.trailing, 12)
        .padding(.top, 10)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

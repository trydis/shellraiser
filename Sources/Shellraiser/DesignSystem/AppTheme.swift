import SwiftUI
import AppKit

/// Shared visual tokens and reusable chrome helpers for the app shell.
enum AppTheme {
    static let canvas = Color(nsColor: NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1))
    static let panel = Color(nsColor: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.15, alpha: 0.92))
    static let panelRaised = Color(nsColor: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.21, alpha: 0.90))
    static let panelSoft = Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.14, alpha: 0.28))
    static let stroke = Color.white.opacity(0.08)
    static let highlight = Color(nsColor: NSColor(calibratedRed: 0.92, green: 0.68, blue: 0.37, alpha: 1))
    static let highlightSoft = Color(nsColor: NSColor(calibratedRed: 0.86, green: 0.52, blue: 0.28, alpha: 1))
    static let textPrimary = Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1))
    static let textSecondary = Color(nsColor: NSColor(calibratedWhite: 0.72, alpha: 1))

    /// Primary chrome gradient used for elevated cards.
    static let panelGradient = LinearGradient(
        colors: [panelRaised.opacity(0.96), panel.opacity(0.92)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent gradient used for controls and active states.
    static let accentGradient = LinearGradient(
        colors: [highlight, highlightSoft],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// Atmospheric backdrop that gives the desktop shell depth behind the terminal panes.
struct AppBackdrop: View {
    var body: some View {
        ZStack {
            AppTheme.canvas
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.clear,
                    AppTheme.highlightSoft.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.highlight.opacity(0.28), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 280
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: -280, y: -220)
                .blur(radius: 24)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.25, green: 0.43, blue: 0.82).opacity(0.22), Color.clear],
                        center: .center,
                        startRadius: 16,
                        endRadius: 300
                    )
                )
                .frame(width: 640, height: 640)
                .offset(x: 340, y: -160)
                .blur(radius: 28)

            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.18))
                .ignoresSafeArea()

            Canvas { context, size in
                let step: CGFloat = 36
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }

                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }

                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.03)),
                    lineWidth: 0.5
                )
            }
            .ignoresSafeArea()
        }
    }
}

/// Rounded card treatment used across sidebar, headers, and sheets.
struct ChromeCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.panelGradient)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppTheme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 16)
    }
}

extension View {
    /// Applies the shared chrome card appearance.
    func chromeCard() -> some View {
        modifier(ChromeCardModifier())
    }
}

/// Capsule-style icon button treatment for pane and header controls.
struct ChromeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary.opacity(configuration.isPressed ? 0.76 : 1))
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.06 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.stroke, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Filled accent button treatment for primary actions.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.accentGradient.opacity(configuration.isPressed ? 0.84 : 1))
            )
            .shadow(color: AppTheme.highlight.opacity(0.28), radius: 16, x: 0, y: 10)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Small metric pill used for queue and pane counts.
struct StatPill: View {
    let title: String
    let value: String
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppTheme.textSecondary)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(emphasized ? Color.black.opacity(0.84) : AppTheme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(emphasized ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.08)))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AppTheme.stroke, lineWidth: emphasized ? 0 : 1)
        )
    }
}

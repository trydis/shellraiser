import SwiftUI

/// Sheet used to create a workspace.
struct NewWorkspaceSheet: View {
    var onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        WorkspaceNameSheet(
            title: "New Workspace",
            message: "Start a fresh cluster of panes and terminal sessions.",
            actionTitle: "Create",
            value: $name
        ) {
            onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workspace" : name)
            dismiss()
        }
    }
}

/// Sheet used to rename a workspace.
struct RenameWorkspaceSheet: View {
    var name: String
    var onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        WorkspaceNameSheet(
            title: "Rename Workspace",
            message: "Adjust the label without disturbing the running sessions.",
            actionTitle: "Rename",
            value: $value
        ) {
            onRename(value.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        }
        .onAppear {
            value = name
        }
    }
}

/// Shared sheet scaffold for workspace naming flows.
struct WorkspaceNameSheet: View {
    let title: String
    let message: String
    let actionTitle: String
    @Binding var value: String
    let onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)

            TextField("Name", text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AppTheme.stroke, lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(ChromeTextButtonStyle())

                Button(actionTitle) {
                    onSubmit()
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(minWidth: 380)
        .chromeCard()
        .padding(20)
        .background {
            AppBackdrop()
        }
    }
}

/// Secondary button style used inside workspace naming sheets.
struct ChromeTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.stroke, lineWidth: 1)
            )
    }
}

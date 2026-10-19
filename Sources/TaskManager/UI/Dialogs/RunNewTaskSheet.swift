import AppKit
import SwiftUI

/// "Create new task" — the Windows Run dialog.
struct RunNewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var command = ""
    @State private var asAdmin = false
    @State private var error: String?
    @State private var running = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppGlyph().frame(width: 28, height: 28)
                Text("Create new task")
                    .font(.system(size: 18, weight: .semibold))
            }
            Text("Type the name of a program, folder, document, or Internet resource, and Task Manager will open it for you.")
                .font(.system(size: 12.5))
                .foregroundStyle(Fluent.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("Open:").font(.system(size: 13))
                TextField("", text: $command, prompt: Text("Safari, ~/Documents, https://apple.com, top"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(run)
            }
            Toggle("Create this task with administrative privileges", isOn: $asAdmin)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("OK", action: run)
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || running)
                Button("Cancel") { dismiss() }
                    .buttonStyle(StandardButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Browse…", action: browse)
                    .buttonStyle(StandardButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { focused = true }
    }

    private func run() {
        guard !running else { return }
        running = true
        error = nil
        Task {
            let message = await TaskLauncher.launch(command, asAdmin: asAdmin)
            running = false
            if let message { error = message } else { dismiss() }
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            command = url.path
        }
    }
}

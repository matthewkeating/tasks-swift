import SwiftUI
import KeyboardShortcuts

// SettingsFormView is a sheet (modal panel) presented inside the main window —
// the same presentation style as TaskFormView — rather than a separate macOS
// Settings window. It exposes the global hotkey recorders.
//
// Each `KeyboardShortcuts.Recorder` is self-contained: clicking it captures the
// next key combo and persists it for the given shortcut name, after which the
// handlers registered in GlobalHotkey use the new binding automatically — no extra
// wiring needed here.
struct SettingsFormView: View {

    // `@Environment(\.dismiss)` reads the action that closes the current sheet, so
    // the Done button (and Escape) can dismiss the panel. Same approach as
    // TaskFormView.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("Keyboard Shortcuts")
                .font(.title2)
                .bold()

            // `Form` lays the recorders out as standard label/control rows with
            // aligned labels — the conventional look for a settings panel.
            Form {
                KeyboardShortcuts.Recorder("Show / hide Tasks:", name: .toggleTasks)
                KeyboardShortcuts.Recorder("New task:", name: .newTask)
            }
            // `.formStyle(.columns)` keeps the labels and recorders in two tidy
            // aligned columns inside the sheet.
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    // Return closes the panel. The recorders intercept key events
                    // only while actively recording, so this doesn't interfere.
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

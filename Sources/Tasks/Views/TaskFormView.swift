import SwiftUI

// `TaskFormMode` is an enum (enumeration) that describes whether the form is
// being used to create a new task or edit an existing one.
//
// The `.edit` case carries an *associated value* — a `GoogleTask` instance.
// Associated values let enum cases carry data, making this a concise alternative
// to a separate `isEditing: Bool` flag and an optional `taskToEdit: GoogleTask?`.
enum TaskFormMode {
    case create
    case edit(GoogleTask)
}

// TaskFormView is a sheet (modal panel) used for both creating and editing tasks.
// It is presented by TaskListView and dismissed when the user taps Cancel or submits.
struct TaskFormView: View {

    // Reads the TaskStore from the environment so `submit()` can call store methods.
    @Environment(TaskStore.self) private var store

    // `@Environment(\.dismiss)` reads the SwiftUI environment's dismiss action —
    // a function that closes the current sheet or popover when called. The
    // `\.dismiss` syntax is a key path — it identifies which environment value to
    // read from the SwiftUI environment dictionary.
    @Environment(\.dismiss) private var dismiss

    // `mode` is a constant (`let`) because it is set when the form is created and
    // never changes while the form is open. The caller decides create vs. edit.
    let mode: TaskFormMode

    // Called with the new task's ID after a successful create. Nil in edit mode.
    var onCreated: ((GoogleTask.ID) -> Void)? = nil

    // These two `@State` properties hold the current values of the form fields.
    // They start with sensible defaults and are optionally pre-filled by
    // `populateIfEditing()` when the form opens in edit mode.
    @State private var title = ""
    @State private var notes = ""

    enum Field { case title, notes }
    @FocusState private var focusedField: Field?

    // A computed property that returns `true` when the form is in edit mode.
    // `if case .edit = mode` is pattern matching — it checks whether `mode`
    // matches the `.edit` case (ignoring the associated value). This avoids
    // needing to write a full `switch` statement just to test the case.
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {

        // `alignment: .leading` left-aligns all children (instead of the default
        // centre alignment). This gives the form a standard left-anchored layout.
        VStack(alignment: .leading, spacing: 20) {

            // A nested VStack groups the label and input field together with
            // tighter spacing (6pt) than the outer VStack (20pt).
            VStack(alignment: .leading, spacing: 6) {

                // `TextField` is a single-line text input.
                // The first argument is placeholder text shown when the field is empty.
                // `text: $title` is a two-way binding — changes the user makes in the
                // field are automatically written back to `title`, and changes to
                // `title` in code are reflected in the field.
                TextField("Title", text: $title)
                    // `.title2` is a larger system text style; `.bold()` weights it.
                    // Using a semantic style (rather than a fixed point size) keeps
                    // the field in step with the user's Dynamic Type settings.
                    .font(.title2)
                    .bold()
                    // `.plain` removes the default rounded border and background,
                    // leaving just the text. `.padding(6)` restores the inset the
                    // border used to provide so text isn't flush to the edge.
                    .textFieldStyle(.plain)
                    .padding(6)
                    // Draw a 1pt border only while this field has focus. When it
                    // doesn't, we stroke with `.clear` so the layout stays identical
                    // (no jump) but nothing is visible. `Color.accentColor` is the
                    // system accent — the same colour used for selected list rows
                    // and the prominent Return-key button.

                    .focused($focusedField, equals: .title)
            }

            VStack(alignment: .leading, spacing: 6) {

                // `TextEditor` is a multi-line text input, unlike `TextField`.
                // It also uses a two-way binding via `$notes`.
                TextEditor(text: $notes)
                    .font(.body)
                    // `.frame(height: 80)` fixes the editor's height so it doesn't
                    // grow unbounded as the user types.
                    .frame(height: 200)
                    // TextEditor has no built-in placeholder (unlike TextField), so
                    // we fake one by overlaying a Text that's shown only while `notes`
                    // is empty. `alignment: .topLeading` sits it where typed text begins.
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Notes...")
                                .font(.body)
                                // `.placeholder` is the system placeholder colour,
                                // matching the greyed-out hint in TextFields.
                                .foregroundStyle(.placeholder)
                                // These insets line the placeholder up with where
                                // TextEditor actually draws its text (slightly inset
                                // from the frame); nudge if it doesn't align exactly.
                                .padding(.top, 0)
                                .padding(.leading, 5)
                                // `.allowsHitTesting(false)` lets clicks pass through
                                // to the TextEditor underneath so it can still focus.
                                .allowsHitTesting(false)
                        }
                    }
                    // `.scrollIndicators(.hidden)` hides the scrollbar that
                    // TextEditor shows while scrolling its content.
                    .scrollIndicators(.hidden)
                    .focused($focusedField, equals: .notes)
            }

            // `HStack` arranges its children horizontally, left to right.
            HStack {
                // `Spacer()` is a flexible invisible view that expands to fill
                // available space, pushing the buttons to the right edge.
                Spacer()

                Button("Cancel") { dismiss() }
                    // `.keyboardShortcut(.escape)` binds the Escape key to this
                    // button, so pressing Escape dismisses the form — a standard
                    // macOS convention for cancelling a sheet.
                    .keyboardShortcut(.escape)

                Button(isEditing ? "Save" : "Add") { submit() }
                    // `.return` binds the Return/Enter key to the submit button.
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    // `.disabled(_:)` prevents the button from being tapped when
                    // the condition is true. `trimmingCharacters(in: .whitespaces)`
                    // strips leading/trailing spaces so a title of only spaces
                    // is treated as empty rather than valid input.
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)

        // `.onAppear` runs the closure once, right after the view is first rendered.
        // This is the right place to pre-fill the form fields when editing an
        // existing task, because `@State` properties are set up by the time
        // `onAppear` fires.
        .onAppear { populateIfEditing() }
    }

    // Pre-fills the form fields with data from the existing task when in edit mode.
    // Does nothing in create mode.
    private func populateIfEditing() {
        // `guard case .edit(let task) = mode` is pattern matching with binding —
        // it checks whether `mode` is `.edit`, and if so, extracts the associated
        // `GoogleTask` into a local constant `task`. If `mode` is `.create`,
        // the guard fails and we exit early via `return`.
        guard case .edit(let task) = mode else { return }

        title = task.title
        // `task.notes` is Optional (the API may not return it). `?? ""` provides
        // an empty string so the TextEditor always has a non-nil binding.
        notes = task.notes ?? ""
    }

    // Validates and submits the form, then dismisses the sheet.
    private func submit() {
        // Strip whitespace from both ends before saving — prevents tasks with
        // accidental leading/trailing spaces from being created.
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        // Start an async task to call the store (network call), then immediately
        // dismiss the sheet without waiting for it to finish. The store update
        // happens in the background and the UI refreshes when it completes.
        _Concurrency.Task {
            // `switch` on the mode to decide whether to create or update.
            switch mode {
            case .create:
                if let id = await store.createTask(
                    title: trimmedTitle,
                    // Pass `nil` for notes if the field is empty — sending an
                    // empty string vs. nil can behave differently in some APIs.
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                ) {
                    onCreated?(id)
                }
            case .edit(let task):
                await store.updateTask(
                    task,
                    title: trimmedTitle,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
            }
        }

        // `dismiss()` closes the sheet immediately (before the async task above
        // completes). This feels snappy to the user; the list updates in the
        // background once the network call returns.
        dismiss()
    }

}

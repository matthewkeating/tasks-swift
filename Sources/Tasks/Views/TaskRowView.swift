import SwiftUI

// TaskRowView renders a single row in the task list. It shows a completion
// toggle button on the left, the task title and optional notes/due date in the
// middle, and supports a right-click context menu for editing and deleting.
struct TaskRowView: View {

    @Environment(TaskStore.self) private var store

    // The task to display. This is a `let` constant — the row receives a task
    // and displays it, but never mutates it directly. Changes go through the store.
    let task: GoogleTask
    var isSelected: Bool = false

    // The row no longer owns the edit sheet or delete confirmation. Instead it
    // reports the user's intent up to TaskListView, which presents a single
    // shared sheet/alert. This keeps mouse-driven actions (these buttons, the
    // context menu) and keyboard-driven actions (Return/Delete on the selected
    // row) flowing through one code path, and lets the parent adjust selection
    // after a delete.
    var onEdit: () -> Void
    var onDelete: () -> Void

    // Called when the row should become the selection — currently just the
    // double-click-to-edit path, since List's native click handling already
    // covers a plain single click.
    var onSelect: () -> Void = {}

    // Reports inline title-editing state up to TaskListView, so its own
    // Return handler (which opens the edit sheet for the selected task) can
    // stay out of the way while this row is already mid-edit.
    var onEditingChanged: (Bool) -> Void = { _ in }

    // Drives inline title editing, entered via a double-click on the title text.
    // `editedTitle` holds the in-progress text until it's committed (Return, or
    // losing focus) or discarded (Escape).
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @FocusState private var isTitleFieldFocused: Bool

    var body: some View {

        // `alignment: .top` aligns the checkbox button and the text VStack at
        // their top edges, so the button doesn't drift to the vertical centre
        // when the task has multiple lines of text.
        HStack(alignment: .center, spacing: 10) {

            // The completion toggle — a plain circular button that switches
            // between a filled checkmark (done) and an empty circle (not done).
            Button(action: {
                // Capture `task` into a local constant before entering the async
                // closure. Closures in Swift capture variables by reference by
                // default, but `task` is a struct (value type), so this copy is
                // a safety measure to ensure the closure uses the task value at
                // the moment the button was tapped, not a potentially changed
                // value by the time the async work runs.
                let t = task
                _Concurrency.Task { await store.toggleComplete(t) }
            }) {
                // Switches the SF Symbol and colour based on completion state.
                // `task.isDone ? A : B` is a ternary — returns A when done, B when not.
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            // `.plain` removes the default button background and border, leaving
            // just the icon. Without this, SwiftUI would render a visible button
            // frame around the circle image inside a List row.
            .buttonStyle(.plain)

            // The text content: title, optional notes, optional due date.
            VStack(alignment: .leading, spacing: 2) {

                if isEditingTitle {
                    TextField("Title", text: $editedTitle, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .focused($isTitleFieldFocused)
                        // A vertical-axis TextField treats Return as "insert a
                        // newline" rather than "submit" — `.onSubmit` no longer
                        // fires — so Return is intercepted here to commit instead.
                        .onKeyPress(.return) {
                            commitTitleEdit()
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            cancelTitleEdit()
                            return .handled
                        }
                        // Losing focus (e.g. clicking elsewhere) commits, the same
                        // as pressing Return — only Escape discards the edit.
                        .onChange(of: isTitleFieldFocused) {
                            if !isTitleFieldFocused { commitTitleEdit() }
                        }
                } else {
                    Text(task.title)
                        // `.strikethrough` draws a line through the text when `task.isDone`
                        // is true — a common visual convention for completed items.
                        .strikethrough(task.isDone, color: .secondary)
                        // Dim the title when done to reinforce that it's complete.
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .onTapGesture(count: 1) { startTitleEdit() }
                        // `.simultaneousGesture` (rather than a plain `.onTapGesture(count: 1)`)
                        // fires immediately on every tap instead of waiting out the system's
                        // double-click interval to rule out a second tap — that wait is what
                        // caused a noticeable lag before the row selected.
                        .simultaneousGesture(TapGesture().onEnded { onSelect() })
                        // Signals the title is editable on double-click: swap in
                        // the I-beam (text-edit) cursor while hovering, and push
                        // it back to the arrow on exit. `NSCursor.push`/`.pop`
                        // form a stack, so every push here is paired with a pop
                        // rather than an unconditional `.set()`, which would leave
                        // the I-beam showing after the mouse leaves the row.
                        .onHover { isHovering in
                            if isHovering {
                                NSCursor.iBeam.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }

                // Show the due date if the task has one.
                if let due = task.due {
                    Text(formattedDue(due))
                        // `.caption2` is smaller than `.caption` — the smallest
                        // Dynamic Type style, suitable for tertiary metadata.
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            if isSelected {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "document")
                .foregroundStyle(.secondary)
                .font(.caption)
                .opacity((task.notes?.isEmpty == false) ? 1 : 0)  // The note icon now always occupies its space — it's just invisible when the task has no notes

        }
        // `.vertical` padding adds space above and below each row, preventing
        // the text from feeling cramped inside the List.
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

        // `.contentShape(Rectangle())` tells SwiftUI that the entire row rectangle
        // is tappable/hoverable — not just the visible subviews. Without this,
        // the context menu would only trigger over the text and button, not the
        // empty space to the right of them.
        .contentShape(Rectangle())

        // `.contextMenu` attaches a right-click (or long-press) menu to the row.
        .contextMenu {
            Button("Edit…", action: onEdit)

            // `Divider` renders a horizontal separator line between menu items.
            Divider()

            // `role: .destructive` tints the button red and signals to SwiftUI
            // (and accessibility tools) that this action is irreversible. On
            // macOS, it renders the label in red.
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    // Enters inline editing: seeds the field with the current title and hands it
    // keyboard focus (which also selects the text, macOS's default TextField
    // behaviour on focus).
    private func startTitleEdit() {
        onSelect()
        onEditingChanged(true)
        editedTitle = task.title
        isEditingTitle = true
        isTitleFieldFocused = true
    }

    // Saves the edited title, unless it's empty or unchanged. Notes are passed
    // through unchanged since `updateTask` patches both fields together.
    private func commitTitleEdit() {
        isEditingTitle = false
        onEditingChanged(false)
        let trimmed = editedTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        let t = task
        _Concurrency.Task { await store.updateTask(t, title: trimmed, notes: t.notes) }
    }

    // Discards the in-progress edit without saving — bound to Escape.
    private func cancelTitleEdit() {
        isEditingTitle = false
        onEditingChanged(false)
    }

    // Converts the ISO 8601 date string from the Google Tasks API into a
    // human-readable label like "Due Jun 25, 2026".
    private func formattedDue(_ rfc3339: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]

        // If the string can't be parsed (malformed API response), fall back to
        // displaying the raw string rather than crashing or showing nothing.
        guard let date = iso.date(from: rfc3339) else { return rfc3339 }

        // `date.formatted(date:time:)` uses the system locale to format the date
        // in the user's preferred language and region automatically.
        // `.abbreviated` produces a short month name (e.g. "Jun" not "June").
        // `.omitted` skips the time component entirely.
        return "Due " + date.formatted(date: .abbreviated, time: .omitted)
    }
}

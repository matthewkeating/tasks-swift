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

                Text(task.title)
                    // `.strikethrough` draws a line through the text when `task.isDone`
                    // is true — a common visual convention for completed items.
                    .strikethrough(task.isDone, color: .secondary)
                    // Dim the title when done to reinforce that it's complete.
                    .foregroundStyle(task.isDone ? .secondary : .primary)

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

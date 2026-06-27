import SwiftUI
import Combine

// TaskListView is the detail column of the NavigationSplitView. It shows the
// tasks for whichever list the user has selected in the sidebar, with toolbar
// controls to add a task and toggle visibility of completed ones.
struct TaskListView: View {

    @Environment(TaskStore.self) private var store

    // Drives the sheet that presents TaskFormView. Setting this to `true`
    // causes the `.sheet` modifier below to present the form.
    @State private var showingAddTask = false

    // When `false`, completed tasks are filtered out of the list. The user
    // can toggle this with the toolbar button. Persisted in UserDefaults so the
    // choice is remembered across app launches.
    @AppStorage("showCompleted") private var showCompleted = false
    @State private var selectedTaskID: GoogleTask.ID?

    // Drive the shared edit sheet and delete confirmation. Both the mouse paths
    // (row buttons / context menu) and the keyboard paths (Return / Delete on the
    // selected row) set these, so there's a single source of truth for "edit
    // this task" and "delete this task".
    @State private var taskToEdit: GoogleTask?
    @State private var taskToDelete: GoogleTask?

    // Tracks whether the task List holds keyboard focus. Driving it to `true`
    // when the list first appears means Up/Down, Return, and Delete work without
    // first clicking a row. Scoped to the list's appearance (not data refreshes
    // or list switches) so it never steals focus from the edit sheet or sidebar.
    @FocusState private var isListFocused: Bool

    private var activeTasks: [GoogleTask] {
        store.selectedTasks.filter { !$0.isDone }
    }

    private var completedTasks: [GoogleTask] {
        store.selectedTasks
            .filter { $0.isDone }
            .sorted { ($0.completed ?? "") > ($1.completed ?? "") }
    }

    // The tasks as they appear on screen, top to bottom: active tasks first,
    // then completed ones when that section is shown. Used to resolve the
    // selected task and to pick the next selection after a delete.
    private var visibleTasks: [GoogleTask] {
        activeTasks + (showCompleted ? completedTasks : [])
    }

    // The currently selected task, searched across both sections.
    private var selectedTask: GoogleTask? {
        visibleTasks.first { $0.id == selectedTaskID }
    }

    var body: some View {
        Group {
            if store.isLoading {
                // Show a spinner centred in the detail column while tasks load.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if store.selectedTasks.isEmpty {
                // `ContentUnavailableView` is a built-in SwiftUI view (added in
                // macOS 14) that renders a centred icon, title, and description
                // for empty states — a standard "nothing here yet" placeholder.
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "checkmark.circle",
                    description: Text("Add a task to get started.")
                )
                .toolbarBackground(.hidden, for: .windowToolbar)

            } else {
                // `List` renders a scrollable list of rows. Using `ForEach`
                // inside `List` iterates over `visibleTasks` and creates one
                // `TaskRowView` per task. `ForEach` requires each item to be
                // `Identifiable` (have a unique `id` property) so SwiftUI can
                // efficiently update only the rows that changed.
                List(selection: $selectedTaskID) {
                    Section {
                        ForEach(activeTasks) { task in
                            TaskRowView(
                                task: task,
                                isSelected: task.id == selectedTaskID,
                                onEdit: { taskToEdit = task },
                                onDelete: { taskToDelete = task }
                            )
                            .listSectionSeparator(.hidden, edges: .top)
                        }
                        .onMove { source, destination in
                            guard let sourceIndex = source.first else { return }
                            let movedTask = activeTasks[sourceIndex]

                            var tasks = activeTasks
                            tasks.move(fromOffsets: source, toOffset: destination)
                            let newIndex = tasks.firstIndex { $0.id == movedTask.id }!
                            let afterTask = newIndex > 0 ? tasks[newIndex - 1] : nil

                            _Concurrency.Task { await store.moveTask(movedTaskID: movedTask.id, afterTaskID: afterTask?.id) }
                        }
                    }

                    if showCompleted {
                        ForEach(completedTasks) { task in
                            TaskRowView(
                                task: task,
                                isSelected: task.id == selectedTaskID,
                                onEdit: { taskToEdit = task },
                                onDelete: { taskToDelete = task }
                            )
                        }
                    }
                }
                // `.inset` is a list style that shows rows with inset (indented)
                // separators — a common appearance in macOS detail views.
                .listStyle(.inset)
                // Stop a click in the empty area below the rows from clearing the
                // selection. The List is backed by an NSTableView; setting its
                // `allowsEmptySelection` to `false` makes AppKit refuse to drop to
                // an empty selection on a background click, so the current task
                // stays selected with no flicker. The legitimate "nothing selected"
                // states (no tasks, all filtered out) coincide with the table
                // having zero rows, where this flag has nothing to override.
                .background(TableConfigurator { tableView in
                    tableView.allowsEmptySelection = false
                })
                // Keyboard navigation for the selected row. `.onKeyPress` only
                // fires while the List holds keyboard focus, so these don't
                // interfere with typing in the edit sheet or elsewhere. Returning
                // `.ignored` when nothing is selected lets the keystroke pass
                // through to its default handling.
                //
                // Return → edit the selected task.
                .onKeyPress(.return) {
                    guard let task = selectedTask else { return .ignored }
                    taskToEdit = task
                    return .handled
                }
                // Delete (Backspace) → confirm, then delete the selected task.
                // `.onDeleteCommand` is the macOS-specific hook for the Delete
                // key on a focused list; `.onKeyPress(.delete)` doesn't fire here
                // because the List's underlying table view consumes that key.
                .onDeleteCommand {
                    guard let task = selectedTask else { return }
                    taskToDelete = task
                }
                // Bind the List into the focus system, then claim focus once it
                // appears. The `DispatchQueue.main.async` defers the assignment to
                // the next runloop tick — setting `@FocusState` during the same
                // pass the view is first installed often doesn't take.
                .focused($isListFocused)
                .onAppear {
                    DispatchQueue.main.async { isListFocused = true }
                }
            }
        }
        // Keep a sensible row selected so keyboard navigation (Up/Down, Return,
        // Delete) is live without first clicking a row. Runs on appear and
        // whenever the visible set changes: switching lists (`selectedListID`),
        // tasks finishing their async load (`selectedTasks`), or toggling the
        // completed section (`showCompleted`).
        .onAppear { selectFirstTaskIfNeeded() }
        .onChange(of: store.selectedListID) { selectFirstTaskIfNeeded() }
        .onChange(of: store.selectedTasks) { selectFirstTaskIfNeeded() }
        .onChange(of: showCompleted) { selectFirstTaskIfNeeded() }

        // The global "new task" hotkey (see GlobalHotkey). When this view is on
        // screen the notification arrives directly; when the hotkey had to reopen a
        // closed window, this view instead picks up the pending request as it
        // appears. Both paths just open the add-task sheet.
        .onReceive(NotificationCenter.default.publisher(for: .newTaskHotkey)) { _ in
            showingAddTask = true
            NewTaskRequest.markHandled()
        }
        .onAppear {
            if NewTaskRequest.consume() { showingAddTask = true }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddTask = true }) {
                    Label("New Task", systemImage: "plus")
                }
            }
        }

        // Publishes a "new task" action into the scene's focused values so the
        // File ▸ New Task menu item (defined in Tasks.swift) can trigger the same
        // sheet. `focusedSceneValue` makes it available whenever this view is part
        // of the active scene, regardless of which control holds keyboard focus.
        .focusedSceneValue(\.newTaskAction) { showingAddTask = true }

        // Publishes a binding to `showCompleted` into the scene's focused values
        // so the View ▸ Show Completed menu item can read and flip the same state.
        .focusedSceneValue(\.showCompleted, $showCompleted)

        // `.sheet(isPresented:)` watches the `$showingAddTask` binding. When it
        // becomes `true`, SwiftUI presents the closure's view as a modal sheet.
        // When the sheet is dismissed (by `dismiss()` inside TaskFormView), SwiftUI
        // automatically sets `showingAddTask` back to `false`.
        .sheet(isPresented: $showingAddTask) {
            TaskFormView(mode: .create, onCreated: { id in selectedTaskID = id })
        }

        // Shared edit sheet, presented for whichever task the user chose to edit
        // (via the row's pencil, the context menu, or Return). `item:` presents
        // the sheet whenever `taskToEdit` is non-nil and passes the task in.
        .sheet(item: $taskToEdit) { task in
            TaskFormView(mode: .edit(task))
        }

        // Shared delete confirmation. Bound to `taskToDelete`: presented when
        // non-nil, dismissed when cleared. `presenting:` passes the staged task
        // into the action/message closures.
        .alert(
            "Delete Task",
            isPresented: Binding(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            ),
            presenting: taskToDelete
        ) { task in
            // `.defaultAction` makes Return trigger Delete; `.cancelAction` makes
            // Escape trigger Cancel — so the dialog is fully keyboard-operable.
            // Return confirms here because the user reached this dialog by
            // pressing Delete, so confirming with Return is the expected flow.
            Button("Delete", role: .destructive) { performDelete(task) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: { task in
            Text("Are you sure you want to permanently delete \u{201C}\(task.title)\u{201D}?")
        }

        // `.alert` presents a modal error dialog when `store.error` is non-nil.
        //
        // `.constant(store.error != nil)` creates a read-only binding that is
        // `true` whenever there is an error. A constant binding never writes back
        // to a source of truth — the alert is dismissed programmatically by
        // setting `store.error = nil` in the OK button's action instead.
        .alert("Error", isPresented: .constant(store.error != nil)) {
            Button("OK") { store.error = nil }
        } message: {
            // `store.error` is an Optional String. `?? ""` provides an empty
            // string fallback so `Text` always receives a non-optional value.
            Text(store.error ?? "")
        }
    }

    // Selects the first visible task when nothing is selected, or when the
    // current selection has scrolled out of view (e.g. after switching lists or
    // hiding the completed section). Leaves a still-valid selection untouched so
    // it doesn't fight the user's own navigation.
    private func selectFirstTaskIfNeeded() {
        if let id = selectedTaskID, visibleTasks.contains(where: { $0.id == id }) {
            return
        }
        selectedTaskID = visibleTasks.first?.id
    }

    // Deletes the task and, when it was the selected row, moves the selection to
    // a sensible neighbour so keyboard navigation can continue uninterrupted.
    private func performDelete(_ task: GoogleTask) {
        // Only adjust selection if the task being deleted is the selected one —
        // deleting some other row (e.g. via its context menu) shouldn't move the
        // user's current selection.
        if task.id == selectedTaskID {
            selectedTaskID = nextSelectionID(after: task)
        }
        _Concurrency.Task { await store.deleteTask(task) }
    }

    // Picks the selection that should follow `task`'s removal: the next visible
    // row, or the previous one if `task` was last. Returns `nil` when `task` was
    // the only row, leaving nothing selected.
    private func nextSelectionID(after task: GoogleTask) -> GoogleTask.ID? {
        let tasks = visibleTasks
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return selectedTaskID
        }
        if index + 1 < tasks.count { return tasks[index + 1].id }
        if index - 1 >= 0 { return tasks[index - 1].id }
        return nil
    }
}

import SwiftUI

// ContentView is the root view shown after the user signs in. Its sole job is
// to create the TaskStore and show a loading spinner until it's ready, then
// hand off to MainView.
//
// SwiftUI views are value types (structs), not classes. They are cheap to create
// and SwiftUI recreates them frequently — what persists between re-renders is the
// state stored in property wrappers like `@State` and `@Environment`.
struct ContentView: View {

    // `@Environment` reads a value that was injected into the SwiftUI environment
    // by an ancestor view — in this case the `authManager` injected in Tasks.swift.
    // `private` means only this struct can access it.
    @Environment(AuthManager.self) private var auth

    // `@State` gives this view ownership of `store`. It starts as `nil` because
    // the TaskStore must be created asynchronously (it needs the auth object, which
    // is only available once the view appears). The Optional (`?`) means it can be
    // absent until initialisation completes.
    @State private var store: TaskStore?

    // `body` is the single required property of the `View` protocol. SwiftUI calls
    // this to get the current UI description whenever state changes.
    var body: some View {

        // `Group` is a transparent container — it has no visual appearance of its
        // own. It's used here to apply the `.task` and `.toolbar` modifiers to
        // both branches of the `if/else` at once, without wrapping them in a
        // visible container like VStack or ZStack.
        Group {
            // `if let store` is optional binding — this branch runs only once
            // `store` has been assigned a non-nil value.
            if let store {
                MainView()
                    // Inject the ready store into the environment so MainView
                    // and all its descendants can read it via `@Environment`.
                    .environment(store)
            } else {
                // Show a spinner with a label while the task store is loading.
                // `maxWidth/maxHeight: .infinity` expands the view to fill all
                // available space, keeping the spinner centred in the window.
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        // `.task` attaches an async task to this view's lifetime. SwiftUI starts
        // the task when the view appears and cancels it if the view disappears.
        // This is the idiomatic place to kick off async work in SwiftUI.
        .task {
            // Create the store and assign it to trigger a re-render (the Group
            // above will switch from ProgressView to MainView).
            let s = TaskStore(auth: auth)
            store = s
            // `await` suspends here while the network call fetches the user's
            // task lists. Because `.task` runs in an async context, this is safe.
            await s.loadTaskLists()
        }

    }
}

// MainView owns the two-pane navigation layout: a sidebar list of task lists
// on the left and the selected list's tasks on the right.
struct MainView: View {

    @Environment(AuthManager.self) private var auth
    // Reads the TaskStore from the environment (injected by ContentView above).
    @Environment(TaskStore.self) private var store

    // for determining if the OS is in light or dark mode
    @Environment(\.colorScheme) private var colorScheme

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var keyMonitor: Any?

    // Drives the "New List" alert and holds the in-progress name the user types.
    @State private var showingAddList = false
    @State private var newListName = ""

    // The list the user has asked to delete, if any. Non-nil presents the
    // confirmation dialog; the dialog clears it back to nil when dismissed.
    @State private var listPendingDeletion: TaskList?

    // Drives the settings sheet, presented in-window like TaskFormView. Set to
    // true by the app menu's "Settings…" item via the published focused action.
    @State private var showingSettings = false

    var body: some View {

        // `@Bindable` is needed to create two-way `$` bindings to properties of
        // an `@Observable` object. Without it, `$store.selectedListID` wouldn't
        // compile because `@Environment` gives a read-only reference by default.
        // The `var` re-declaration (shadowing the property above) is intentional
        // and required by Swift to attach the wrapper.
        @Bindable var store = store

        // `NavigationSplitView` creates the classic two-column (sidebar + detail)
        // layout used in most macOS and iPad apps. The sidebar closure provides
        // the left column; `detail:` provides the right column.
        NavigationSplitView(columnVisibility: $columnVisibility) {

            // `List` renders a scrollable, selectable list of items.
            // `store.taskLists` is the data source (an Array of TaskList).
            // `selection: $store.selectedListID` is a two-way binding — tapping
            // a row writes that row's identifier back to `store.selectedListID`.
            List(store.taskLists, selection: $store.selectedListID) { list in
                let activeCount = store.tasksByList[list.id]?.filter { !$0.isDone }.count ?? 0
                HStack {
                    Text(list.title)
                    Spacer()
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                // `.tag` associates this row with an identifier value. The List
                // uses tags to know which item is selected and to write the
                // correct value into the `selection` binding.
                .tag(list.id)
                // Right-clicking a row reveals a context menu. The Delete item is
                // marked `.destructive` (rendered in red) and, rather than deleting
                // immediately, stashes the list in `listPendingDeletion` to trigger
                // the confirmation dialog below.
                .contextMenu {
                    Button(role: .destructive) {
                        listPendingDeletion = list
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            // Sets a minimum and preferred width for the sidebar column.
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            // `.sidebar` applies the platform-standard sidebar appearance
            // (translucent background, slightly smaller text, etc.).
            .listStyle(.sidebar)
            // extend the background color to the top of sidebar and set a darker color for
            // the sidebar when in dark mode
            .scrollContentBackground(.hidden)
            .background(
                (colorScheme == .dark
                  ? Color(red: 20/255, green: 20/255, blue: 20/255)
                  : Color(nsColor: .controlBackgroundColor))
              .ignoresSafeArea()

            )
            // `.safeAreaInset` pins a view to the bottom edge of the sidebar
            // *outside* the scrolling area — the macOS-standard place for a
            // list's "+" control (as seen in Reminders and Notes).
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        newListName = ""
                        showingAddList = true
                    } label: {
                        Label("New List", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .padding(4)
                    }
                    // `.borderless` removes the default button chrome so it reads as
                    // a lightweight toolbar action rather than a prominent button.
                    .buttonStyle(.borderless)
                    .help("New List")
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
            // The "New List" alert. macOS alerts can host a `TextField`, giving us
            // a single-field name prompt without a full sheet. Create is guarded
            // against empty/whitespace names since alert buttons can't be disabled.
            .alert("New List", isPresented: $showingAddList) {
                TextField("List name", text: $newListName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    let name = newListName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    _Concurrency.Task { await store.createTaskList(title: name) }
                }
            } message: {
                Text("Enter a name for your new list.")
            }
            // The delete confirmation. `presenting:` passes the pending list into
            // both the buttons and the message closures, and the derived binding
            // clears `listPendingDeletion` when the dialog is dismissed.
            .confirmationDialog(
                "Delete “\(listPendingDeletion?.title ?? "")”?",
                isPresented: Binding(
                    get: { listPendingDeletion != nil },
                    set: { if !$0 { listPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: listPendingDeletion
            ) { list in
                // `.defaultAction` makes Return trigger Delete; `.cancelAction`
                // makes Escape trigger Cancel — so the dialog is fully
                // keyboard-operable, matching the task-deletion confirmation.
                Button("Delete", role: .destructive) {
                    _Concurrency.Task { await store.deleteTaskList(list) }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { }
                    .keyboardShortcut(.cancelAction)
            } message: { _ in
                Text("This removes the list and all of its tasks.")
            }
        } detail: {
            TaskListView()
                // Set the window/navigation title to the selected list's name.
                .navigationTitle(currentTitle)
        }

        // `.onChange(of:)` runs a closure whenever the specified value changes.
        // The closure receives both the old value (`_`, ignored here) and the
        // new value (`newID`). This is how we trigger a task fetch when the user
        // selects a different list in the sidebar.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            _Concurrency.Task { await store.loadTaskLists() }
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            _Concurrency.Task { await store.loadTaskLists() }
        }
        .onChange(of: store.selectedListID) { _, newID in
            if let id = newID {
                // `_Concurrency.Task` creates a new async task to call the
                // `async` function `store.loadTasks`. The `_Concurrency.` prefix
                // disambiguates Swift's built-in `Task` type from any other
                // `Task` type that might exist in scope (e.g. a Google Task model).
                _Concurrency.Task { await store.loadTasks(listID: id) }
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
                      (1...9).contains(digit) else { return event }
                let index = digit - 1
                guard index < store.taskLists.count else { return event }
                store.selectedListID = store.taskLists[index].id
                return nil
            }
        }
        .onDisappear {
            if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        }

        // Publish the "open settings" action so the app menu's Settings… item can
        // trigger the in-window sheet (see Tasks.swift). Mirrors how TaskListView
        // publishes its New Task action.
        .focusedSceneValue(\.showSettingsAction) { showingSettings = true }

        // The settings sheet itself, presented inside the main window.
        .sheet(isPresented: $showingSettings) {
            SettingsFormView()
        }
    }

    // A computed property that derives the navigation title from the currently
    // selected list. `first(where:)` searches the array for the matching item.
    // Optional chaining (`?.title`) safely handles the case where no list matches,
    // and `?? "Tasks"` provides a sensible fallback title.
    private var currentTitle: String {
        store.taskLists.first(where: { $0.id == store.selectedListID })?.title ?? "Tasks"
    }
}


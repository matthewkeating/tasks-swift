import Foundation

// `@Observable` generates the property observation infrastructure so SwiftUI
// views re-render automatically when any property they read changes.
//
// `@MainActor` constrains all methods and property accesses on this class to
// run on the main thread (the UI thread). This is important for two reasons:
//   1. SwiftUI requires that all state mutations driving the UI happen on the
//      main thread — violating this causes runtime warnings or crashes.
//   2. It means callers don't have to think about threading; they can `await`
//      any method here and be guaranteed the result is written safely.
//
// Because `@MainActor` handles thread safety at the class level, `Sendable`
// is not needed here (unlike GoogleTasksClient, which is called from any thread).
@Observable
@MainActor
final class TaskStore {

    // All properties below are the observable state that drives the UI.
    // Any view reading one of these will re-render when it changes.

    // The user's task lists, populated by `loadTaskLists()`.
    var taskLists: [TaskList] = []

    // A dictionary mapping each list's ID to its array of tasks.
    // Using a dictionary avoids storing duplicate list IDs and allows O(1)
    // lookup by list ID (instead of searching an array every time).
    // `[String: [GoogleTask]]` means: keys are Strings, values are arrays of GoogleTask.
    var tasksByList: [String: [GoogleTask]] = [:]

    // The ID of whichever list the user has selected in the sidebar.
    // Optional because no list is selected when the app first launches.
    var selectedListID: String?

    // `true` while the initial task list fetch is in progress, so the UI can
    // show a spinner instead of an empty state.
    var isLoading = false

    // Holds a human-readable error message when any network call fails.
    // The UI observes this and presents an alert when it becomes non-nil.
    var error: String?

    // A computed property that returns the tasks for the currently selected list.
    // Views use this instead of reading `tasksByList[selectedListID]` directly,
    // which would require them to handle the nested optionals themselves.
    var selectedTasks: [GoogleTask] {
        // `guard let` exits early with an empty array if no list is selected.
        guard let id = selectedListID else { return [] }
        // Dictionary subscript returns an Optional — `?? []` provides an empty
        // array fallback if no tasks have been fetched for this list yet.
        return tasksByList[id] ?? []
    }

    // The client that supplies task data. Typed as the `TasksClient` protocol
    // rather than the concrete `GoogleTasksClient` so the store doesn't care
    // which implementation it's talking to — the real API client or the
    // in-memory mock. `private` because only TaskStore needs to call it; the
    // rest of the app goes through the store's higher-level methods.
    private let client: TasksClient

    // The auth manager, retained so we can sign the user out when the server
    // rejects our credentials (see `handle(_:)`). Held even in mock mode — it's
    // never asked to sign out there because the mock client never throws auth
    // errors.
    private let auth: AuthManager

    // Creates the store and wires up the data client. When `DevConfig.useMockData`
    // is set (via the `-mock` launch argument), it injects the in-memory
    // `MockTasksClient` — which never touches the keychain or network, so no
    // password prompt appears. Otherwise it builds the real `GoogleTasksClient`
    // backed by the given auth manager.
    init(auth: AuthManager) {
        self.auth = auth
        if DevConfig.useMockData {
            self.client = MockTasksClient()
        } else {
            self.client = GoogleTasksClient(auth: auth)
        }
    }

    // MARK: - Error handling

    // Central handling for any error thrown by the data client.
    //
    // Authentication failures get special treatment: when the user's Google
    // session has expired or been revoked, every network call would otherwise
    // throw and surface a cryptic "The operation couldn't be completed.
    // (NSURLErrorDomain error 403.)" alert — once per refresh, which with the
    // 15-second poll means the alert reappears constantly. Instead we sign the
    // user out, which flips `AuthManager.isSignedIn` and returns the app to the
    // sign-in screen so they can re-authenticate cleanly.
    //
    // All other errors keep the existing behaviour: store a human-readable
    // message for the error alert to display.
    private func handle(_ error: Error) {
        if isAuthError(error) {
            auth.signOut()
            // Drop any stale error so the sign-in screen isn't showing an alert.
            self.error = nil
        } else {
            self.error = error.localizedDescription
        }
    }

    // Returns `true` when `error` means the user's Google session is no longer
    // valid — either the API rejected the token (HTTP 401 Unauthorized or 403
    // Forbidden, thrown by `GoogleTasksClient.validate`) or the token refresh
    // itself reported that re-authentication is required.
    private func isAuthError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        if urlError.code == .userAuthenticationRequired { return true }
        return urlError.code.rawValue == 401 || urlError.code.rawValue == 403
    }

    // MARK: - Load

    // Fetches the user's task lists, selects the first one if none is selected,
    // then immediately loads the tasks for that list.
    func loadTaskLists() async {
        let initialLoad = taskLists.isEmpty
        if initialLoad { isLoading = true }
        defer { if initialLoad { isLoading = false } }

        do {
            let fetchedLists = try await client.fetchTaskLists()
            if fetchedLists != taskLists {
                taskLists = fetchedLists
            }

            // Auto-select the first list on first launch (when nothing is selected yet).
            // `taskLists.first?.id` uses optional chaining — if the list is empty,
            // the whole expression is nil and `selectedListID` stays nil.
            if selectedListID == nil {
                selectedListID = taskLists.first?.id
            }

            // Fetch tasks for all lists concurrently so sidebar counts are
            // populated immediately, not just for the selected list.
            await withTaskGroup(of: Void.self) { group in
                for list in taskLists {
                    group.addTask { await self.loadTasks(listID: list.id) }
                }
            }
        } catch {
            // Route through `handle` so an expired Google session signs the user
            // out rather than repeatedly popping a "403" alert on every poll.
            handle(error)
        }
    }

    // Fetches and stores the tasks for a specific list. Called when the user
    // taps a different list in the sidebar, or after `loadTaskLists` on launch.
    func loadTasks(listID: String) async {
        do {
            let fetched = try await client.fetchTasks(listID: listID)
            if fetched != tasksByList[listID] ?? [] {
                tasksByList[listID] = fetched
            }
        } catch {
            handle(error)
        }
    }

    // MARK: - List CRUD

    // Creates a new task list, appends it to the local cache, and selects it so
    // the user lands in their new (empty) list immediately. The server assigns
    // the list's ID, which is why we use the returned value rather than a local one.
    func createTaskList(title: String) async {
        do {
            let newList = try await client.createTaskList(title: title)
            taskLists.append(newList)
            // Seed an empty task array so the sidebar count renders as 0, not blank.
            tasksByList[newList.id] = []
            selectedListID = newList.id
        } catch {
            handle(error)
        }
    }

    // Deletes a task list (and all of its tasks) from the server, then removes it
    // from the local cache. If the deleted list was the selected one, selection
    // moves to a remaining neighbour so the detail pane never points at a list
    // that no longer exists.
    func deleteTaskList(_ list: TaskList) async {
        do {
            try await client.deleteTaskList(listID: list.id)

            // Choose a replacement selection *before* mutating the array, but only
            // when we're deleting the list that's currently selected.
            if selectedListID == list.id, let idx = taskLists.firstIndex(where: { $0.id == list.id }) {
                // The lists that will remain after removal, in their existing order.
                let remaining = taskLists.filter { $0.id != list.id }
                // Prefer the neighbour just above the deleted list; fall back to the
                // new first list, or nil when no lists remain.
                let newIndex = max(0, idx - 1)
                selectedListID = newIndex < remaining.count ? remaining[newIndex].id : remaining.first?.id
            }

            taskLists.removeAll { $0.id == list.id }
            // Free the cached tasks for the deleted list so they aren't retained.
            tasksByList[list.id] = nil
        } catch {
            handle(error)
        }
    }

    // MARK: - CRUD

    // Creates a new task in the currently selected list and inserts it at the
    // top of the local cache so the UI updates immediately.
    @discardableResult
    func createTask(title: String, notes: String?) async -> GoogleTask.ID? {
        // If somehow no list is selected, bail out — there's nowhere to create the task.
        guard let listID = selectedListID else { return nil }

        let create = TaskCreate(title: title, notes: notes)
        do {
            let newTask = try await client.createTask(listID: listID, task: create)

            // `tasksByList[listID, default: []]` reads the array for this list,
            // or an empty array if the key doesn't exist yet — avoiding a force-
            // unwrap. `.insert(at: 0)` places the new task at the top of the list.
            tasksByList[listID, default: []].insert(newTask, at: 0)
            return newTask.id
        } catch {
            handle(error)
            return nil
        }
    }

    // Sends a PATCH request with updated fields for an existing task, then
    // replaces the old version in the local cache with the server's response.
    func updateTask(_ task: GoogleTask, title: String, notes: String?) async {
        guard let listID = selectedListID else { return }

        // Only the fields we want to change are included in the patch — the
        // server leaves all other fields on the task untouched.
        let patch = TaskPatch(title: title, notes: notes)
        do {
            let updated = try await client.updateTask(listID: listID, taskID: task.id, patch: patch)
            // Use the server's response (not our local patch) as the source of
            // truth — the server may normalise or add fields we didn't send.
            replace(updated, in: listID)
        } catch {
            handle(error)
        }
    }

    // Toggles a task between completed and needsAction status.
    func toggleComplete(_ task: GoogleTask) async {
        guard let listID = selectedListID else { return }
        do {
            // Declare `updated` as a `var`-style local with an explicit type so
            // Swift knows the type before either branch of the `if` assigns to it.
            let updated: GoogleTask
            if task.isDone {
                // Already done — mark it as needing action (un-complete it).
                updated = try await client.uncompleteTask(listID: listID, taskID: task.id)
            } else {
                // Not done — mark it as completed.
                updated = try await client.completeTask(listID: listID, taskID: task.id)
            }
            replace(updated, in: listID)
        } catch {
            handle(error)
        }
    }


    // Moves a task to a new position within the current list.
    //
    // `movedTaskID` identifies the task being repositioned.
    // `afterTaskID` is the ID of the task that should immediately precede the moved
    // task in its new position. Pass `nil` to move the task to the very beginning.
    //
    // The local cache is updated optimistically (before the network call) so the
    // UI reflects the new order instantly. If the API call fails, the tasks are
    // reloaded from the server to restore the correct order.
    func moveTask(movedTaskID: String, afterTaskID: String?) async {
        guard let listID = selectedListID else { return }

        // Apply the reorder locally before the network round-trip so the UI
        // responds to the drag gesture without any visible delay.
        if var tasks = tasksByList[listID],
           let fromIndex = tasks.firstIndex(where: { $0.id == movedTaskID }) {
            // Remove the task from its current position, then re-insert it at
            // the correct spot relative to `afterTaskID`.
            let task = tasks.remove(at: fromIndex)
            if let afterID = afterTaskID,
               let afterIndex = tasks.firstIndex(where: { $0.id == afterID }) {
                // Insert immediately after the anchor task.
                tasks.insert(task, at: afterIndex + 1)
            } else {
                // `afterTaskID` is nil — move to the top of the list.
                tasks.insert(task, at: 0)
            }
            tasksByList[listID] = tasks
        }

        do {
            let updated = try await client.moveTask(listID: listID, taskID: movedTaskID, previousTaskID: afterTaskID)
            // Replace the local copy with the server's response (it may contain
            // updated fields such as a revised position token).
            replace(updated, in: listID)
        } catch {
            handle(error)
            // The optimistic update may now be inconsistent — reload from the
            // server to restore the authoritative order.
            await loadTasks(listID: listID)
        }
    }

    // Deletes a task permanently from the server and removes it from the local cache.
    func deleteTask(_ task: GoogleTask) async {
        guard let listID = selectedListID else { return }
        do {
            try await client.deleteTask(listID: listID, taskID: task.id)

            // `removeAll(where:)` filters out the deleted task in-place.
            // `$0.id == task.id` is the predicate — remove any element whose
            // id matches the deleted task's id. The `?` handles the case where
            // the array for this list is nil (shouldn't happen, but safe).
            tasksByList[listID]?.removeAll { $0.id == task.id }
        } catch {
            handle(error)
        }
    }

    // Finds the position of an updated task in the cache and swaps it in-place,
    // preserving the existing sort order while reflecting the server's latest data.
    private func replace(_ task: GoogleTask, in listID: String) {
        // `firstIndex(where:)` searches the array and returns the index of the
        // first matching element, or `nil` if none is found. `guard let` exits
        // early if the task isn't in the cache (e.g. it was deleted concurrently).
        guard let idx = tasksByList[listID]?.firstIndex(where: { $0.id == task.id }) else { return }

        // Subscript the array at that index and overwrite with the updated task.
        tasksByList[listID]?[idx] = task
    }
}

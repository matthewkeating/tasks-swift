import Foundation

// `MockTasksClient` is a drop-in replacement for `GoogleTasksClient` used during
// UI development. It holds all of its data in memory, so it never touches the
// network or the keychain — which means launching the app with this client wired
// in skips the OAuth/keychain password prompt entirely.
//
// Crucially, it isn't just a static snapshot: create, update, complete, move, and
// delete all mutate the in-memory store and return the modified task. That means
// the full UI (adding rows, toggling checkboxes, drag-to-reorder) behaves exactly
// as it would against the real API, just without the round-trip.
//
// It's implemented as an `actor` rather than a plain class because the protocol
// requires `Sendable` conformance: the store may call these methods from
// background tasks. An actor serialises all access to its mutable state, giving
// us thread-safety for free without resorting to `@unchecked Sendable`. Because
// every protocol method is already `async`, callers `await` them just as they
// would the real client — no call-site changes are needed.
actor MockTasksClient: TasksClient {

    // The seed task lists shown in the sidebar.
    private var lists: [TaskList] = [
        TaskList(id: "inbox", title: "My Tasks"),
        TaskList(id: "work",  title: "Work"),
        TaskList(id: "shop",  title: "Shopping"),
    ]

    // Tasks keyed by list ID, mirroring `TaskStore.tasksByList`. The `position`
    // strings are simple zero-padded numbers so the store's lexicographic sort
    // ("00000" < "00001" < …) keeps them in the intended order.
    private var tasksByList: [String: [GoogleTask]] = [
        "inbox": [
            .mock(id: "t1", title: "Buy milk",            position: "00000"),
            .mock(id: "t2", title: "Call the dentist",    notes: "Re: cleaning appointment", position: "00001"),
            .mock(id: "t3", title: "Renew passport",      position: "00002"),
            .mock(id: "t4", title: "File expense report", done: true, position: "00003"),
        ],
        "work": [
            .mock(id: "t5", title: "Review PR #42",       position: "00000"),
            .mock(id: "t6", title: "Write design doc",    notes: "Mock-data injection", position: "00001"),
            .mock(id: "t7", title: "Reply to Sarah",      done: true, position: "00002"),
        ],
        "shop": [
            .mock(id: "t8", title: "Coffee beans",        position: "00000"),
            .mock(id: "t9", title: "Olive oil",           position: "00001"),
        ],
    ]

    // A monotonically increasing counter used to mint unique IDs for newly
    // created tasks, so each one is distinct from the seed data and from each other.
    private var nextID = 100

    // MARK: - Task Lists

    func fetchTaskLists() async throws -> [TaskList] {
        lists
    }

    func createTaskList(title: String) async throws -> TaskList {
        // Mint a fresh ID (sharing the same counter as task creation) and append
        // the new list with an empty task array, mirroring the real API.
        let created = TaskList(id: "mock-list-\(nextID)", title: title)
        nextID += 1
        lists.append(created)
        tasksByList[created.id] = []
        return created
    }

    func deleteTaskList(listID: String) async throws {
        // Drop both the list and its tasks, just as deleting a list server-side
        // discards every task inside it.
        lists.removeAll { $0.id == listID }
        tasksByList[listID] = nil
    }

    // MARK: - Tasks

    func fetchTasks(listID: String) async throws -> [GoogleTask] {
        // Mirror the real client: return an empty array for an unknown list ID
        // rather than throwing.
        tasksByList[listID] ?? []
    }

    func createTask(listID: String, task: TaskCreate) async throws -> GoogleTask {
        // Mint a fresh ID and build a task from the create payload. New tasks go
        // to the top of the list, so give them a position that sorts first.
        let created = GoogleTask.mock(
            id: "mock-\(nextID)",
            title: task.title,
            notes: task.notes,
            position: "-00001"   // sorts before "00000", i.e. at the very top
        )
        nextID += 1
        tasksByList[listID, default: []].insert(created, at: 0)
        return created
    }

    func updateTask(listID: String, taskID: String, patch: TaskPatch) async throws -> GoogleTask {
        // Locate the task and apply only the non-nil fields of the patch, matching
        // the PATCH semantics of the real API.
        guard var task = task(taskID, in: listID) else { throw MockError.notFound }
        if let title = patch.title { task.title = title }
        if let notes = patch.notes { task.notes = notes }
        if let status = patch.status, let parsed = GoogleTask.TaskStatus(rawValue: status) {
            task.status = parsed
            // The real API stamps a completion timestamp; reproduce that so the
            // store's "completed tasks sort by completion time" logic has data.
            task.completed = parsed == .completed ? Self.now() : nil
        }
        replace(task, in: listID)
        return task
    }

    func completeTask(listID: String, taskID: String) async throws -> GoogleTask {
        try await updateTask(listID: listID, taskID: taskID, patch: TaskPatch(status: "completed"))
    }

    func uncompleteTask(listID: String, taskID: String) async throws -> GoogleTask {
        try await updateTask(listID: listID, taskID: taskID, patch: TaskPatch(status: "needsAction"))
    }

    func moveTask(listID: String, taskID: String, previousTaskID: String?) async throws -> GoogleTask {
        guard var tasks = tasksByList[listID],
              let fromIndex = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw MockError.notFound
        }

        // Pull the task out, then re-insert it after `previousTaskID` (or at the
        // front when that's nil) — the same contract the real `moveTask` honours.
        let moved = tasks.remove(at: fromIndex)
        if let previousTaskID, let afterIndex = tasks.firstIndex(where: { $0.id == previousTaskID }) {
            tasks.insert(moved, at: afterIndex + 1)
        } else {
            tasks.insert(moved, at: 0)
        }

        // Renumber every task's position so the store's lexicographic sort agrees
        // with the new array order.
        for index in tasks.indices {
            tasks[index].position = String(format: "%05d", index)
        }
        tasksByList[listID] = tasks

        // Return the moved task with its freshly assigned position.
        return tasks.first { $0.id == taskID } ?? moved
    }

    func deleteTask(listID: String, taskID: String) async throws {
        tasksByList[listID]?.removeAll { $0.id == taskID }
    }

    // MARK: - Helpers

    // Looks up a single task by ID within a list, or nil if absent.
    private func task(_ id: String, in listID: String) -> GoogleTask? {
        tasksByList[listID]?.first { $0.id == id }
    }

    // Overwrites a task in place, preserving its position in the array.
    private func replace(_ task: GoogleTask, in listID: String) {
        guard let index = tasksByList[listID]?.firstIndex(where: { $0.id == task.id }) else { return }
        tasksByList[listID]?[index] = task
    }

    // An RFC 3339 timestamp for the current moment, matching the string format the
    // Google Tasks API uses for the `completed` field.
    private static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // A minimal error type so the async methods have something to throw when a
    // task ID can't be found — keeps the mock honest about failure cases.
    enum MockError: Error {
        case notFound
    }
}

// A convenience factory for building `GoogleTask` values in test/mock contexts
// without spelling out every field at each call site. Defaults cover the common
// case (an incomplete task with no notes or due date).
extension GoogleTask {
    static func mock(
        id: String,
        title: String,
        notes: String? = nil,
        done: Bool = false,
        due: String? = nil,
        position: String? = nil
    ) -> GoogleTask {
        GoogleTask(
            id: id,
            title: title,
            notes: notes,
            status: done ? .completed : .needsAction,
            due: due,
            completed: done ? ISO8601DateFormatter().string(from: Date()) : nil,
            position: position
        )
    }
}

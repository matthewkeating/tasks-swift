import Foundation

// `TasksClient` is the abstraction that decouples `TaskStore` from any one
// concrete data source. Instead of `TaskStore` building a `GoogleTasksClient`
// itself (and therefore always requiring auth + the network), it accepts
// *anything* that conforms to this protocol. That lets us inject either:
//
//   • `GoogleTasksClient` — the real implementation that talks to Google's API.
//   • `MockTasksClient`    — an in-memory fake used for UI testing, which never
//                            touches the keychain or the network.
//
// The method surface here is copied verbatim from `GoogleTasksClient`, so that
// class already satisfies the protocol — see the empty conformance below.
//
// `Sendable` mirrors the requirement on `GoogleTasksClient`: because the store
// may call these methods from background tasks, every conforming type must be
// safe to share across concurrency domains.
protocol TasksClient: Sendable {

    // MARK: - Task Lists
    func fetchTaskLists() async throws -> [TaskList]
    func createTaskList(title: String) async throws -> TaskList
    func deleteTaskList(listID: String) async throws

    // MARK: - Tasks
    func fetchTasks(listID: String) async throws -> [GoogleTask]
    func createTask(listID: String, task: TaskCreate) async throws -> GoogleTask
    func updateTask(listID: String, taskID: String, patch: TaskPatch) async throws -> GoogleTask
    func completeTask(listID: String, taskID: String) async throws -> GoogleTask
    func uncompleteTask(listID: String, taskID: String) async throws -> GoogleTask
    func moveTask(listID: String, taskID: String, previousTaskID: String?) async throws -> GoogleTask
    func deleteTask(listID: String, taskID: String) async throws
}

// `GoogleTasksClient` already declares every method the protocol requires with
// matching signatures, so this empty extension is all that's needed to mark it
// as a conforming type. No method bodies are repeated.
extension GoogleTasksClient: TasksClient {}

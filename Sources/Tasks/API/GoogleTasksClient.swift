import Foundation

// `final` means this class cannot be subclassed — it's a performance hint to the
// Swift compiler and signals that the class is complete as-is.
//
// `Sendable` is a Swift concurrency protocol that guarantees this type is safe to
// share across concurrent tasks (threads). The compiler enforces this by requiring
// all stored properties to themselves be Sendable (or immutable).
final class GoogleTasksClient: Sendable {

    // The base URL for all Google Tasks API v1 requests. The `!` force-unwraps the
    // optional returned by `URL(string:)` — safe here because the literal is known
    // valid at compile time.
    private let base = URL(string: "https://tasks.googleapis.com/tasks/v1")!

    // Injected AuthManager that provides fresh OAuth access tokens. Storing it as a
    // `let` (constant) satisfies the Sendable requirement — immutable references are
    // always safe to share.
    private let auth: AuthManager

    // The designated initialiser. Swift requires you to initialise every stored
    // property before the object is usable; assigning `auth` here satisfies that.
    init(auth: AuthManager) {
        self.auth = auth
    }

    // MARK: - Task Lists

    // Fetches all task lists owned by the authenticated user.
    //
    // `async` means this function can suspend (pause) while waiting for network
    // responses without blocking the calling thread.
    // `throws` means it can propagate errors to the caller using Swift's error
    // handling system — callers must use `try`.
    // The return type `[TaskList]` is an Array of TaskList model objects.
    func fetchTaskLists() async throws -> [TaskList] {
        // Build the endpoint URL by appending a path component to the base URL.
        // `@me` is a Google API alias meaning "the currently authenticated user".
        let url = base.appendingPathComponent("users/@me/lists")

        // `await` suspends execution here until the network response arrives.
        // `try` propagates any thrown errors (network failures, bad status codes, etc.)
        // up to our caller.
        let data = try await get(url: url)

        // Decode the raw JSON bytes into a Swift model. JSONDecoder maps JSON keys to
        // Swift property names automatically (by default, using exact-match naming).
        let response = try JSONDecoder().decode(TaskListsResponse.self, from: data)

        // `response.items` is an Optional ([TaskList]?) — it may be nil if the API
        // returns no lists. The `?? []` nil-coalescing operator returns an empty array
        // as a safe default instead of nil.
        return response.items ?? []
    }

    // Creates a new task list with the given title. The Google Tasks API assigns
    // the list's `id`, so we decode and return the server's response (which the
    // caller needs in order to select and load the new list).
    func createTaskList(title: String) async throws -> TaskList {
        let url = base.appendingPathComponent("users/@me/lists")
        let body = try JSONEncoder().encode(TaskListCreate(title: title))
        let data = try await post(url: url, body: body)
        return try JSONDecoder().decode(TaskList.self, from: data)
    }

    // Permanently deletes a task list along with every task it contains. The
    // server returns no body on success (HTTP 204), so there's nothing to decode.
    func deleteTaskList(listID: String) async throws {
        let url = base.appendingPathComponent("users/@me/lists/\(listID)")
        try await delete(url: url)
    }

    // MARK: - Tasks

    // Fetches all tasks (including completed and hidden ones) from a specific list.
    // `listID` is the opaque string identifier returned by the Google Tasks API.
    func fetchTasks(listID: String) async throws -> [GoogleTask] {
        // URLComponents lets us safely build a URL with query parameters without
        // manually percent-encoding characters. The `!` is safe because we know the
        // base URL is valid and the path is a simple string.
        var components = URLComponents(
            url: base.appendingPathComponent("lists/\(listID)/tasks"),
            resolvingAgainstBaseURL: false
        )!

        // Query items are the key=value pairs that appear after `?` in a URL.
        // These tell the Google API to include completed and hidden tasks and cap
        // results at 100 items per page.
        components.queryItems = [
            URLQueryItem(name: "showCompleted", value: "true"),
            URLQueryItem(name: "showHidden", value: "true"),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "orderBy", value: "position")
        ]

        // `components.url` is Optional because URLComponents can fail to produce a
        // valid URL. The `!` is safe here because we know the components are valid.
        let data = try await get(url: components.url!)
        let response = try JSONDecoder().decode(TasksResponse.self, from: data)
        return (response.items ?? []).sorted { lhs, rhs in
            switch (lhs.isDone, rhs.isDone) {
            case (false, true):  return true
            case (true, false):  return false
            case (false, false): return (lhs.position ?? "") < (rhs.position ?? "")
            case (true, true):   return (lhs.completed ?? "") > (rhs.completed ?? "")
            }
        }
    }

    // Creates a new task in the given list.
    // `TaskCreate` is a model object representing the fields required to create a task
    // (e.g. title, due date). It is encoded to JSON and sent as the request body.
    // Returns the newly created task as returned by the server (with its assigned ID).
    func createTask(listID: String, task: TaskCreate) async throws -> GoogleTask {
        let url = base.appendingPathComponent("lists/\(listID)/tasks")

        // JSONEncoder converts the Swift struct into JSON bytes (Data) for the body.
        let body = try JSONEncoder().encode(task)
        let data = try await post(url: url, body: body)
        return try JSONDecoder().decode(GoogleTask.self, from: data)
    }

    // Partially updates an existing task using HTTP PATCH.
    // Unlike PUT (full replacement), PATCH only sends the fields you want to change —
    // any property not included in `TaskPatch` is left unchanged on the server.
    func updateTask(listID: String, taskID: String, patch: TaskPatch) async throws -> GoogleTask {
        let url = base.appendingPathComponent("lists/\(listID)/tasks/\(taskID)")
        let body = try JSONEncoder().encode(patch)
        let data = try await httpPatch(url: url, body: body)
        return try JSONDecoder().decode(GoogleTask.self, from: data)
    }

    // Permanently deletes a task. The server returns no body on success (HTTP 204),
    // so this function has no return value — the `Void` return is implicit.
    func deleteTask(listID: String, taskID: String) async throws {
        let url = base.appendingPathComponent("lists/\(listID)/tasks/\(taskID)")
        try await delete(url: url)
    }

    // Marks a task as completed by patching its status to "completed" — the string
    // value expected by the Google Tasks API.
    func completeTask(listID: String, taskID: String) async throws -> GoogleTask {
        let patch = TaskPatch(status: "completed")
        return try await updateTask(listID: listID, taskID: taskID, patch: patch)
    }

    // Reverts a completed task back to active by patching its status to "needsAction"
    // — the Google Tasks API term for an incomplete task.
    func uncompleteTask(listID: String, taskID: String) async throws -> GoogleTask {
        let patch = TaskPatch(status: "needsAction")
        return try await updateTask(listID: listID, taskID: taskID, patch: patch)
    }

        // Moves a task to a new position within its list.
    //
    // `previousTaskID` is the ID of the task that should immediately precede the
    // moved task in its new position. Pass `nil` to move the task to the first
    // position in the list.
    //
    // The Google Tasks API uses a POST with no request body; the target position is
    // communicated entirely via the `previous` query parameter.
    func moveTask(listID: String, taskID: String, previousTaskID: String?) async throws -> GoogleTask {
        // Build the URL for the move endpoint. `URLComponents` handles percent-encoding
        // of the query parameter value in case it contains special characters.
        var components = URLComponents(
            url: base.appendingPathComponent("lists/\(listID)/tasks/\(taskID)/move"),
            resolvingAgainstBaseURL: false
        )!

        // Only add the `previous` query parameter when we have a value — omitting it
        // entirely tells the API to move the task to the first position.
        if let previousTaskID {
            components.queryItems = [URLQueryItem(name: "previous", value: previousTaskID)]
        }

        // The move endpoint expects a POST with an empty body; `Data()` satisfies that.
        let data = try await post(url: components.url!, body: Data())
        return try JSONDecoder().decode(GoogleTask.self, from: data)
    }

    // MARK: - HTTP helpers

    // Builds a URLRequest with an Authorization header and optional JSON body.
    // This is `private` — it's an implementation detail not exposed to callers outside
    // this class. The `async throws` signature means fetching a fresh token can both
    // suspend and fail.
    private func request(url: URL, method: String, body: Data? = nil) async throws -> URLRequest {
        // Ask AuthManager for a non-expired OAuth token, waiting (suspending) if a
        // refresh is in progress.
        let token = try await auth.freshAccessToken()

        // URLRequest is a value type (struct) in Swift, so `var` is required to
        // mutate it after creation.
        var req = URLRequest(url: url)
        req.httpMethod = method

        // The Bearer token scheme is the standard way to pass OAuth 2.0 tokens.
        // The server uses this header to verify the request is authenticated.
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // `if let body` is optional binding — this block only runs when `body` is
        // non-nil, unwrapping the value into a local constant also named `body`.
        if let body {
            req.httpBody = body
            // Tell the server the body is JSON so it parses it correctly.
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    // Performs an HTTP GET request and returns the raw response bytes.
    private func get(url: URL) async throws -> Data {
        let req = try await request(url: url, method: "GET")

        // `URLSession.shared` is a singleton HTTP client provided by Foundation.
        // `.data(for:)` is its async/await API — it suspends until the response
        // arrives and returns a tuple of (responseBody, URLResponse).
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response)
        return data
    }

    // Performs an HTTP POST request with a JSON body and returns the response bytes.
    // POST is typically used to create new resources on the server.
    private func post(url: URL, body: Data) async throws -> Data {
        let req = try await request(url: url, method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response)
        return data
    }

    // Performs an HTTP PATCH request with a JSON body and returns the response bytes.
    // Named `httpPatch` (not `patch`) to avoid a name collision with Swift's
    // internal use of "patch" in concurrency contexts.
    private func httpPatch(url: URL, body: Data) async throws -> Data {
        let req = try await request(url: url, method: "PATCH", body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response)
        return data
    }

    // Performs an HTTP DELETE request. DELETE requests have no response body, so
    // the returned `Data` is discarded with `_`.
    private func delete(url: URL) async throws {
        let req = try await request(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: req)
        try validate(response)
    }

    // Checks that the HTTP status code indicates success (200–299).
    // Any other code is treated as an error and thrown to the caller.
    private func validate(_ response: URLResponse) throws {
        // `URLResponse` is the base type; we need `HTTPURLResponse` to access the
        // status code. The `as?` cast returns nil for non-HTTP responses.
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // If the cast or range check fails, extract the status code (or -1 if
            // the cast itself failed) and throw it as a URLError.
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.init(rawValue: code))
        }
        // If the guard passes, this function returns normally (no throw).
    }
}

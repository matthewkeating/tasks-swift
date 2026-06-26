import Foundation

// This file defines the Swift data models that mirror the JSON shapes returned
// by (and sent to) the Google Tasks REST API. Swift's `Codable` system handles
// converting between JSON bytes and these structs automatically.

// MARK: - API Response wrappers

// The Google Tasks API wraps list results in a JSON object with an `items` array:
//   { "items": [ {...}, {...} ] }
// This struct represents that wrapper. `items` is Optional because the API omits
// the key entirely (rather than returning an empty array) when there are no results.
//
// `Decodable` is a protocol that lets `JSONDecoder` automatically populate the
// struct's properties from matching JSON keys. No manual parsing code is needed.
struct TaskListsResponse: Decodable {
    let items: [TaskList]?
}

// Same wrapper pattern for the tasks endpoint, which returns a list of GoogleTask.
struct TasksResponse: Decodable {
    let items: [GoogleTask]?
}

// MARK: - Task List

// Represents one task list (e.g. "My Tasks", "Shopping", "Work").
//
// `Identifiable` — a protocol requiring a property named `id`. SwiftUI uses
// this to uniquely identify items in `List` and `ForEach`, enabling efficient
// row diffing and animation. The `id: String` property below satisfies it.
//
// `Decodable` — enables JSON decoding (described above).
//
// `Hashable` — allows instances to be used as dictionary keys or stored in Sets,
// and is required by `List(selection:)` in SwiftUI when the selection binding
// holds values of this type.
struct TaskList: Identifiable, Decodable, Hashable {
    let id: String
    let title: String

    // `CodingKeys` is a nested enum that maps Swift property names to JSON keys.
    // When the names match exactly (as they do here), a `CodingKeys` enum is
    // technically optional — `Codable` would infer the same mapping automatically.
    // It's included explicitly here to make the mapping visible and easy to modify
    // if the API ever uses different key names (e.g. "taskListId" instead of "id").
    enum CodingKeys: String, CodingKey {
        case id, title
    }
}

// MARK: - Task

// Represents a single task returned from the Google Tasks API.
//
// `id` is `let` (immutable) because a task's identity never changes after
// creation. The remaining properties are `var` (mutable) because they can be
// updated by the user and patched back to the API.
struct GoogleTask: Identifiable, Decodable, Hashable {
    let id: String
    var title: String
    // Optional properties — the API may omit these keys if the task has no
    // notes, due date, or completion timestamp.
    var notes: String?
    var status: TaskStatus
    var due: String?        // ISO 8601 / RFC 3339 date string, e.g. "2026-06-25T00:00:00.000Z"
    var completed: String?  // ISO 8601 timestamp set by the server when the task is completed.
    var position: String?   // Lexicographic sort key; lower value = earlier in list.

    // A convenience computed property that hides the raw status string from the
    // rest of the app. Views and the store can check `task.isDone` instead of
    // comparing strings manually.
    var isDone: Bool { status == .completed }

    // `TaskStatus` is a nested enum that models the two states the Google Tasks
    // API uses for task completion.
    //
    // `String` raw value — each case maps to the exact string the API sends.
    // `Codable` (both Encodable + Decodable) — the JSON decoder will match the
    // raw string value from JSON to the appropriate case automatically.
    enum TaskStatus: String, Codable {
        case needsAction = "needsAction"
        case completed   = "completed"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, status, due, completed, position
    }
}

// MARK: - Request bodies

// `TaskPatch` is the body sent with an HTTP PATCH request to partially update a
// task. Every property is Optional — only non-nil fields are serialised to JSON
// and sent to the server, leaving all other fields on the task unchanged.
//
// `Encodable` (the write-only half of `Codable`) allows `JSONEncoder` to convert
// this struct into JSON bytes for the request body. `Decodable` is not needed
// because we never parse a TaskPatch from a response.
struct TaskPatch: Encodable {
    var title: String?
    var notes: String?
    var status: String?
}

// `TaskCreate` is the body sent with an HTTP POST request to create a new task.
// `title` is non-optional because the Google Tasks API requires it — a task
// must have a title. `notes` and `due` are optional extras.
struct TaskCreate: Encodable {
    var title: String
    var notes: String?
}

// `TaskListCreate` is the body sent with an HTTP POST request to create a new
// task list. The Google Tasks API requires only a title — there are no other
// user-settable fields on a list at creation time.
struct TaskListCreate: Encodable {
    var title: String
}

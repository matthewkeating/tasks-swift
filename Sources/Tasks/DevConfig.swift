import Foundation

// `DevConfig` centralises development-only toggles that are read from the process
// launch arguments. Driving these from launch arguments (rather than a `#if DEBUG`
// constant) means you can flip them per-run by choosing a different debug
// configuration — no code edits or recompiles required.
//
// The flags are wired up in `.vscode/launch.json`: the "Debug Tasks (Mock Data)"
// configuration passes `-mock`, while the plain "Debug Tasks" configuration passes
// nothing and therefore runs against the real Google Tasks API.
enum DevConfig {

    // When `true`, the app skips the sign-in/auth flow and feeds the UI from an
    // in-memory `MockTasksClient` instead of `GoogleTasksClient`. This avoids the
    // keychain password prompt that otherwise appears on every debug launch, which
    // is the whole point when you're only iterating on UI.
    //
    // `ProcessInfo.processInfo.arguments` is the array of command-line arguments
    // the process was launched with; we simply check whether `-mock` is present.
    static var useMockData: Bool {
        ProcessInfo.processInfo.arguments.contains("-mock")
    }
}

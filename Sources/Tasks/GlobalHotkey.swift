import AppKit
import KeyboardShortcuts

// `KeyboardShortcuts.Name` is the library's identifier for a single bindable
// shortcut. Declaring them as static constants gives us one canonical reference to
// use both when registering the handlers and when showing the recorders in Settings.
//
// The `default:` argument seeds each shortcut the first time the app runs (⌥⌘T to
// show/hide, ⌥⌘N for a new task). After that the user's own choice — made via the
// recorder — is persisted in UserDefaults and takes over, so these defaults are
// only ever the starting point.
extension KeyboardShortcuts.Name {
    static let toggleTasks = Self("toggleTasks", default: .init(.t, modifiers: [.command, .option]))
    static let newTask = Self("newTask", default: .init(.n, modifiers: [.command, .option]))
}

// Posted when the "new task" hotkey fires. TaskListView observes this to present
// its add-task sheet. See `NewTaskRequest` for how the window-closed case (where
// no view exists yet to receive this) is handled.
extension Notification.Name {
    static let newTaskHotkey = Notification.Name("newTaskHotkey")
}

// Bridges the global "new task" hotkey to TaskListView's add-task sheet.
//
// The hotkey can fire when the window is visible, merely hidden, or closed
// entirely. For the first two a live TaskListView hears the notification posted by
// `send()` (NotificationCenter delivers it synchronously). For the third there is
// no view yet, so we also leave a one-shot flag that a freshly reopened
// TaskListView consults in `onAppear` via `consume()`.
@MainActor
enum NewTaskRequest {
    private(set) static var isPending = false

    static func send() {
        isPending = true
        // Synchronous: a live TaskListView's `.onReceive` runs (and clears the
        // flag via `markHandled`) before this returns. If none is alive, the post
        // is a no-op and the flag survives for the next `consume()`.
        NotificationCenter.default.post(name: .newTaskHotkey, object: nil)
    }

    // Called by a TaskListView that just appeared; returns true (once) if a
    // request is still waiting to be handled, clearing it in the process.
    static func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }

    // Called by a live TaskListView that handled the notification, so the flag
    // doesn't linger and spuriously fire on a later, unrelated window reopen.
    static func markHandled() {
        isPending = false
    }
}

enum GlobalHotkey {
    // Wires the system-wide hotkeys to their actions. Called once at launch from
    // the AppDelegate. `onKeyUp` (rather than `onKeyDown`) is the convention for an
    // action that shows UI — it fires after the user releases the combo, which
    // feels less twitchy and avoids key-repeat double-firing.
    static func register() {
        // The library invokes these handlers as plain nonisolated closures, so hop
        // onto the main actor before touching NSApp (which is main-actor isolated).
        KeyboardShortcuts.onKeyUp(for: .toggleTasks) {
            Task { @MainActor in toggleVisibility() }
        }
        KeyboardShortcuts.onKeyUp(for: .newTask) {
            Task { @MainActor in requestNewTask() }
        }
    }

    // Flicks the app in and out of the foreground like a scratchpad: if we're
    // already the active app, hide every window so focus returns to whatever the
    // user was doing; otherwise bring ourselves forward.
    @MainActor
    private static func toggleVisibility() {
        if NSApp.isActive {
            NSApp.hide(nil)
        } else {
            bringToFront()
        }
    }

    // Always brings the app forward and asks TaskListView to open the add-task
    // sheet. The flag is set *before* `bringToFront` so that if the window has to
    // be reopened, the fresh TaskListView sees the pending request in `onAppear`.
    @MainActor
    private static func requestNewTask() {
        NewTaskRequest.send()
        bringToFront()
    }

    // Brings the app to the foreground. `unhide` reverses a previous hide,
    // `activate` makes us the frontmost app, and the final step deminiaturizes and
    // raises a window. If the window had been closed (red button / ⌘W),
    // `WindowGroup` has no window to raise, so we ask AppKit to reopen one the same
    // way clicking the Dock icon would.
    @MainActor
    private static func bringToFront() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            // No restorable window exists — replicate the Dock-icon reopen, which
            // prompts SwiftUI's WindowGroup to spawn a fresh window.
            _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
        }
    }
}

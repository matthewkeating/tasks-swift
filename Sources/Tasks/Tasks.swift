import SwiftUI
import GoogleSignIn

// A `FocusedValueKey` lets a view deep in the hierarchy publish a value (here, an
// action closure) that commands defined far away in the App's menu bar can read.
// SwiftUI delivers the value from whichever view currently has scene focus, so the
// File ▸ New Task menu item can run code that lives in TaskListView without having
// to thread a binding down through every intermediate view.
private struct NewTaskActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newTaskAction: (() -> Void)? {
        get { self[NewTaskActionKey.self] }
        set { self[NewTaskActionKey.self] = newValue }
    }
}

// Same idea as `newTaskAction`, but here we publish a `Binding<Bool>` rather than
// a plain closure. A binding is a two-way reference to a piece of state, so the
// View ▸ Show Completed menu item can both read the current value (to show its
// checkmark) and flip it — driving the exact same `showCompleted` state that
// TaskListView owns.
private struct ShowCompletedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showCompleted: Binding<Bool>? {
        get { self[ShowCompletedKey.self] }
        set { self[ShowCompletedKey.self] = newValue }
    }
}

// Required when running as a plain SPM executable (no .app bundle) so that
// macOS treats this process as a regular GUI app with a Dock icon and windows.
// Without this, the default activation policy suppresses all UI.
private class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Disable macOS's automatic window tabbing. Without this, the system adds
        // tab-related items to the View and Window menus ("Show Tab Bar", "Show
        // Next Tab", "Merge All Windows", etc.). This app is single-window, so
        // turning tabbing off removes those menu items entirely.
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

// `@main` marks this struct as the entry point of the app. Swift uses this to
// know where to start execution — it replaces the traditional `main.swift` file.
//
// Conforming to the `App` protocol is what makes a SwiftUI app. You provide a
// `body` property that describes the top-level structure (scenes) of the app.
@main
struct TasksApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Reads the "new task" action published by the currently focused view (see
    // `FocusedValues.newTaskAction`). It is `nil` when no view publishes it — for
    // example on the sign-in screen — which lets us disable the menu item then.
    @FocusedValue(\.newTaskAction) private var newTaskAction

    // The binding to TaskListView's `showCompleted` state, published while that
    // view is on screen. Nil otherwise (e.g. the sign-in screen).
    @FocusedValue(\.showCompleted) private var showCompleted

    // `@State` is a SwiftUI property wrapper that gives a view (or App) ownership
    // of a piece of mutable data. When an `@State` value changes, SwiftUI
    // automatically re-evaluates `body` to reflect the new state.
    //
    // `private` limits access to this property to this struct — it's an
    // implementation detail that nothing outside TasksApp needs to touch.
    //
    // `AuthManager()` calls the initialiser with no arguments, creating a new
    // instance when the app launches.
    @State private var authManager = AuthManager()

    // `body` is the single required property of the `App` protocol. It describes
    // the scenes the app presents. `some Scene` is an opaque return type — it
    // tells the compiler "this returns something that conforms to Scene" without
    // exposing the exact concrete type.
    var body: some Scene {

        // `WindowGroup` is the standard scene for a document-style or single-window
        // app. On macOS it manages the window lifecycle (open, close, restore).
        // The trailing closure provides the root view for each window.
        WindowGroup {

            // Conditional view switching based on authentication state. SwiftUI
            // re-evaluates this `if/else` whenever `authManager.isSignedIn` changes,
            // automatically swapping between the two views.
            Group {
                // `DevConfig.useMockData` short-circuits the auth gate: when the
                // app is launched with `-mock`, the sign-in screen is skipped
                // entirely and ContentView loads straight from the in-memory mock
                // client. This is what makes UI iteration possible without ever
                // entering a password.
                if authManager.isSignedIn || DevConfig.useMockData {
                    // The user is authenticated (or we're in mock mode) — show
                    // the main content.
                    ContentView()
                        // `.environment(_:)` injects `authManager` into the SwiftUI
                        // environment, making it available to ContentView and all of its
                        // descendant views via the `@Environment` property wrapper.
                        .environment(authManager)
                } else {
                    // Not yet signed in — show the Google Sign-In screen.
                    SignInView()
                        .environment(authManager)
                }
            }
            .frame(minWidth: 650, minHeight: 425)
        }

        // `.commands` lets you customise the macOS menu bar for this scene.
        .commands {
            // `CommandGroup(replacing: .newItem)` replaces the built-in "New" menu
            // item (Cmd+N) — which would create a new document window this app
            // doesn't support — with our own "New Task" item. The `.newItem`
            // placement lives at the top of the standard File menu, so providing
            // content here is what makes the File menu appear (and is where the
            // system's standard "Close" item is hosted).
            CommandGroup(replacing: .newItem) {
                Button("New Task") { newTaskAction?() }
                    // `newTaskAction` is published by TaskListView via
                    // `.focusedSceneValue`. It's nil when that view isn't on
                    // screen, so disable the item rather than offer a no-op.
                    .disabled(newTaskAction == nil)
                    .keyboardShortcut("n", modifiers: .command)
            }
            // `.sidebar` is a standard placement inside the View menu (where
            // "Show Sidebar" lives), so adding a group after it puts our toggle in
            // the View menu. A `Toggle` renders as a menu item with a checkmark
            // that reflects the current `showCompleted` value.
            CommandGroup(after: .sidebar) {
                // `showCompleted` is the binding published by TaskListView. When
                // it's nil (no list on screen), fall back to a constant and
                // disable the item so it can't be toggled to no effect.
                Toggle("Show Completed", isOn: showCompleted ?? .constant(false))
                    .disabled(showCompleted == nil)
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Toggle Sidebar") {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])

                // A `Divider` renders as a separator line. Placed at the end of
                // this group, it sits between "Toggle Sidebar" and the system's
                // "Enter Full Screen" item that follows in the View menu.
                Divider()
            }
            CommandGroup(before: .appTermination) {
                Button("Sign Out") { authManager.signOut() }
                Divider()
            }
        }
    }
}

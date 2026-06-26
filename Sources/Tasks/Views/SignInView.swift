import SwiftUI

// SignInView is the first screen the user sees if they are not authenticated.
// It presents a simple centred layout with an icon, title, description, and
// a sign-in button. When the user taps the button, `auth.signIn()` sets
// `auth.isSignedIn = true`, which causes Tasks.swift to swap this view out
// for ContentView automatically.
struct SignInView: View {

    // Reads the AuthManager from the SwiftUI environment (injected in Tasks.swift).
    @Environment(AuthManager.self) private var auth

    var body: some View {

        // `VStack` arranges its children vertically, top to bottom.
        // `spacing: 24` adds 24 points of space between each child view.
        // Points are the unit SwiftUI uses for layout — on a standard display
        // 1 point = 1 pixel; on a Retina display 1 point = 2 pixels.
        VStack(spacing: 24) {

            // `Image(systemName:)` loads an icon from SF Symbols, Apple's built-in
            // icon library. The name "checkmark.circle.fill" is the SF Symbol
            // identifier for a filled circle with a checkmark inside.
            Image(systemName: "checkmark.circle.fill")
                // `.font(.system(size: 64))` controls the size of an SF Symbol
                // image by treating it like text — symbols scale with font size.
                .font(.system(size: 64))
                // `.foregroundStyle(.blue)` sets the icon's colour to the
                // system blue, which automatically adapts to light/dark mode.
                .foregroundStyle(.blue)

            Text("Tasks")
                // `.largeTitle` is one of SwiftUI's dynamic type styles — it
                // uses the system's preferred large title font size, which scales
                // with the user's accessibility text-size setting.
                // `.bold()` is a modifier on the Font that adds bold weight.
                .font(.largeTitle.bold())

            Text("Sign in with your Google account\nto access your task lists.")
                // `\n` is a newline character, splitting the string across two
                // lines. `.multilineTextAlignment(.center)` centres each line
                // horizontally within the text view's frame.
                .multilineTextAlignment(.center)
                // `.secondary` is a semantic colour that renders as a dimmed
                // version of the primary label colour — grey in light mode,
                // a lighter grey in dark mode. Using semantic colours means
                // you don't need separate light/dark mode handling.
                .foregroundStyle(.secondary)

            // A button whose action closure calls `auth.signIn()` when tapped.
            // `action:` takes a closure (a block of code) to run on tap.
            Button(action: { auth.signIn() }) {
                // `Label` combines an icon and a text title in a single view.
                // SwiftUI automatically arranges them appropriately for the context
                // (e.g. icon + text in a button, icon-only in a compact toolbar).
                // `systemImage:` takes an SF Symbol name, same as `Image(systemName:)`.
                Label("Sign in with Google", systemImage: "person.badge.key")
                    // `minWidth: 200` ensures the button is at least 200 points
                    // wide even if the label text is shorter, giving it a
                    // consistent, tap-friendly size.
                    .frame(minWidth: 200)
            }
            // `.borderedProminent` is a built-in button style that renders a
            // filled, coloured background (blue by default) — the standard
            // appearance for a primary call-to-action button on Apple platforms.
            .buttonStyle(.borderedProminent)
            // `.large` makes the button taller with larger text, appropriate
            // for a primary action that should be easy to tap.
            .controlSize(.large)
        }
        // `.padding(48)` adds 48 points of space inside the VStack on all four
        // sides, preventing content from touching the window edges.
        .padding(48)
        // `.frame(width:height:)` fixes the window to exactly 400×360 points.
        // Without this the window would size itself to fit its content, which
        // can produce an awkwardly small or large window on first launch.
        .frame(width: 400, height: 360)
    }
}

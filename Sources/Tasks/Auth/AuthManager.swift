import Foundation
import GoogleSignIn

// `@Observable` is a Swift macro that generates the infrastructure needed for
// SwiftUI to track which properties a view reads and re-render only when those
// properties change.
//
// `@unchecked Sendable` tells the Swift compiler this class is safe to use across
// concurrent threads while opting out of compile-time safety checks. It's needed
// here because GIDSignIn's callbacks run on arbitrary threads and `@Observable`
// storage isn't automatically verified as thread-safe. The `@unchecked` qualifier
// is a promise from the developer to handle any thread-safety concerns manually.
@Observable
final class AuthManager: @unchecked Sendable {

    // These two properties are the observable state that drives the UI.
    // Any SwiftUI view that reads `isSignedIn` or `userEmail` will automatically
    // re-render when they change.
    var isSignedIn: Bool = false
    var userEmail: String = ""

    init() {
        // In mock mode we never talk to Google, so skip restoring the previous
        // sign-in. That call reads the saved refresh token from the keychain,
        // which is exactly what triggers the "auth" keychain password prompt on
        // launch — the thing `-mock` exists to avoid.
        guard !DevConfig.useMockData else { return }
        restorePreviousSignIn()
    }

    // Attempts to restore the last signed-in Google account using a refresh token
    // stored in the system keychain by the GoogleSignIn SDK.
    private func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            guard let self, let user, error == nil else { return }
            self.isSignedIn = true
            self.userEmail = user.profile?.email ?? ""
        }
    }

    // Presents the Google Sign-In sheet to the user.
    @MainActor func signIn() {
        // `NSApplication.shared.keyWindow` is the frontmost active window on
        // macOS — required by the GoogleSignIn SDK as the "presenter" it attaches
        // its sign-in sheet to. If there's no active window (unlikely but possible
        // during app startup), bail out early with `return`.
        guard let presenter = NSApplication.shared.keyWindow else { return }

        GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,   // Optional email pre-fill for the sign-in form.
            // `additionalScopes` requests permission to access Google Tasks on
            // behalf of the user. OAuth scopes are strings that identify which
            // Google APIs the app is allowed to call.
            additionalScopes: ["https://www.googleapis.com/auth/tasks"]
        ) { [weak self] result, error in
            guard let self, let result, error == nil else { return }
            self.isSignedIn = true
            self.userEmail = result.user.profile?.email ?? ""
        }
    }

    // Signs the current user out, clears their tokens from the keychain, and
    // resets the observable state so the UI switches back to SignInView.
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userEmail = ""
    }

    // Returns a valid OAuth access token, refreshing it first if it has expired.
    // Access tokens are short-lived (typically 1 hour); the SDK handles renewal
    // transparently using a long-lived refresh token stored in the keychain.
    //
    // `async throws` means this function can suspend while waiting for the network
    // refresh and can throw an error if the refresh fails or no user is signed in.
    func freshAccessToken() async throws -> String {

        // `withCheckedThrowingContinuation` is a Swift bridge that wraps a
        // callback-based API (like GoogleSignIn's completion handlers) into an
        // `async throws` function. The closure receives a `continuation` object
        // with two methods:
        //   • `continuation.resume(returning:)` — completes successfully, like `return`
        //   • `continuation.resume(throwing:)` — completes with an error, like `throw`
        // Exactly one of these must be called — calling neither hangs the caller
        // forever; calling both crashes.
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.currentUser?.refreshTokensIfNeeded { user, error in
                if let error {
                    // The refresh failed. We want to distinguish two very
                    // different causes so callers can react appropriately:
                    //
                    //   • A transient network problem (offline, timeout, DNS).
                    //     Surfaces as a `URLError`. The refresh token is still
                    //     good — the user shouldn't be signed out just because
                    //     their Wi-Fi dropped — so we propagate it unchanged and
                    //     let `TaskStore` show a normal error alert.
                    //
                    //   • The refresh token itself is invalid or revoked (the
                    //     session was terminated, the password changed, access
                    //     was withdrawn). The SDK reports this as an OAuth/keychain
                    //     error, *not* a `URLError`. There is no recovering without
                    //     re-authenticating, so we normalise it to
                    //     `.userAuthenticationRequired` — the same signal the
                    //     defensive branch below uses — which `TaskStore.isAuthError`
                    //     recognises and turns into a clean sign-out.
                    if error is URLError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: URLError(.userAuthenticationRequired))
                    }
                } else if let token = user?.accessToken.tokenString {
                    // We got a valid token string — return it to the async caller.
                    continuation.resume(returning: token)
                } else {
                    // The SDK returned neither an error nor a token — this shouldn't
                    // happen in practice, but we handle it defensively by throwing a
                    // standard URLError indicating the user needs to authenticate.
                    continuation.resume(throwing: URLError(.userAuthenticationRequired))
                }
            }
        }
    }
}

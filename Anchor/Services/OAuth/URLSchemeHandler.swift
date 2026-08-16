//
//  URLSchemeHandler.swift
//  Anchor
//
//  Receives the `anchor://` redirects that end a browser sign-in and hands them
//  to whichever OAuth flow is waiting.
//
//  The scheme itself is declared in Info.plist (CFBundleURLTypes). macOS routes
//  an `anchor://…` open to `AppDelegate.application(_:open:)`, which forwards
//  here; nothing else in the app touches the URL.
//
//  Only one redirect per flow is ever accepted: a waiter is registered before
//  the browser opens, matched on both its route and its `state`, and removed the
//  moment it resumes. A redirect that matches no waiter is dropped — a teacher
//  reopening an old sign-in link from history cannot make Anchor exchange a
//  stale code.
//

import AppKit
import Foundation

// MARK: - Redirect payload

/// The query parameters an OAuth provider sends back, whichever transport
/// carried them (custom scheme or loopback).
nonisolated struct OAuthRedirect: Sendable {
    var code: String?
    var state: String?
    var error: String?
    var errorDescription: String?

    /// Provider-supplied failure text, preferring the human-readable half.
    var failureMessage: String? {
        guard error != nil || errorDescription != nil else { return nil }
        return errorDescription ?? error
    }

    /// True when the provider reported the teacher declining, rather than a
    /// genuine failure. Google says `access_denied`; Zoom says `user_denied`.
    var isUserDenial: Bool {
        guard let error else { return false }
        return error == "access_denied" || error == "user_denied"
    }

    nonisolated static func parse(_ components: URLComponents?) -> OAuthRedirect {
        let items = components?.queryItems ?? []
        func value(_ name: String) -> String? {
            let raw = items.first { $0.name == name }?.value?.trimmed
            return (raw?.isEmpty ?? true) ? nil : raw
        }
        return OAuthRedirect(
            code: value("code"),
            state: value("state"),
            error: value("error"),
            errorDescription: value("error_description")
        )
    }
}

// MARK: - Errors

/// Transport-level failures, shared by both redirect styles. Each OAuth client
/// maps these onto its own error type before they reach the UI.
nonisolated enum OAuthRedirectError: LocalizedError, Equatable, Sendable {
    /// The teacher closed the browser, or the flow simply never came back.
    case cancelled
    /// The redirect carried a `state` that wasn't the one we sent. Treated as
    /// hostile: the response did not come from the request Anchor made.
    case stateMismatch
    case missingCode
    case provider(String)
    case listenerFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Sign-in didn't finish."
        case .stateMismatch:
            "The sign-in response didn't match the request Anchor sent."
        case .missingCode:
            "The sign-in finished without an authorization code."
        case .provider(let detail):
            detail
        case .listenerFailed(let detail):
            detail
        }
    }
}

// MARK: - Handler

/// Routes `anchor://` callbacks to the flow that is waiting for them.
///
/// A plain class with a lock rather than an actor: `handle(_:)` is called from
/// AppKit's URL delivery on the main thread and has to complete synchronously,
/// while `waitForRedirect` suspends an OAuth actor. A lock spans both without
/// forcing either onto the other's executor.
nonisolated final class URLSchemeHandler: @unchecked Sendable {

    static let shared = URLSchemeHandler()

    /// Must match the CFBundleURLSchemes entry in Info.plist.
    static let scheme = "anchor"

    /// Redirect URI for a provider's app configuration. Paste these verbatim
    /// into the Zoom Marketplace / Google Cloud console.
    static func redirectURI(route: String) -> String {
        "\(scheme)://\(route.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    private struct Waiter {
        let route: String
        let state: String
        let continuation: CheckedContinuation<OAuthRedirect, Error>
    }

    /// A redirect that arrived before its flow got round to waiting for it.
    private struct Delivered {
        let route: String
        let redirect: OAuthRedirect
        let receivedAt: Date
    }

    private var waiters: [UUID: Waiter] = [:]
    /// Held only long enough to cover the gap between opening the browser and
    /// suspending on the response — see `waitForRedirect`.
    private var delivered: [Delivered] = []
    private let lock = NSLock()
    private let timeoutQueue = DispatchQueue(label: "com.anchor.oauth.url-scheme")

    /// How long an unclaimed redirect is worth keeping. Long enough to cover a
    /// redirect that beats its waiter; far too short to be a stale code lying
    /// around after a flow has moved on.
    private static let deliveryGrace: TimeInterval = 30

    private init() {}

    // MARK: Waiting

    /// Registers interest in one redirect and suspends until it arrives.
    ///
    /// - Parameters:
    ///   - route: the path portion of the redirect URI — `oauth/zoom` for
    ///     `anchor://oauth/zoom`.
    ///   - state: the CSRF value sent on the authorization request. A redirect
    ///     carrying anything else fails the wait rather than being exchanged.
    ///   - timeout: how long to wait before giving up on a browser that never
    ///     came back. Five minutes matches the loopback flow.
    ///
    /// A redirect that lands before this is called is not lost: `handle(_:)`
    /// parks it for `deliveryGrace` and it is claimed here on arrival. That
    /// window exists because the browser can come back faster than the calling
    /// flow reaches its own suspension point — the whole round trip is a single
    /// `NSWorkspace.open` away, and on a Zoom session that is already signed in
    /// there is no human in the loop to slow it down.
    func waitForRedirect(
        route: String,
        state: String,
        timeout: TimeInterval = 300
    ) async throws -> OAuthRedirect {
        let id = UUID()
        let normalized = Self.normalize(route: route)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                let alreadyArrived = claimDeliveredLocked(route: normalized)
                if alreadyArrived == nil {
                    waiters[id] = Waiter(route: normalized, state: state, continuation: continuation)
                }
                lock.unlock()

                if let alreadyArrived {
                    continuation.resume(with: Self.validate(alreadyArrived, state: state))
                    return
                }

                timeoutQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.resume(id: id, with: .failure(OAuthRedirectError.cancelled))
                }
            }
        } onCancel: {
            resume(id: id, with: .failure(OAuthRedirectError.cancelled))
        }
    }

    // MARK: Receiving

    /// Entry point from `AppDelegate.application(_:open:)`.
    ///
    /// - Returns: whether the URL belonged to a flow Anchor was waiting on. A
    ///   `false` here means the URL went nowhere, which is worth knowing when
    ///   debugging a redirect that appears to do nothing.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == Self.scheme else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // `anchor://oauth/zoom` parses as host "oauth" + path "/zoom", so the
        // route has to be rebuilt from both halves.
        let route = Self.normalize(route: [components?.host, components?.path]
            .compactMap { $0 }
            .joined(separator: "/"))

        let redirect = OAuthRedirect.parse(components)

        lock.lock()
        let match = waiters.first { $0.value.route == route }
        if let match {
            waiters.removeValue(forKey: match.key)
        } else {
            // Nothing waiting *yet*. Park it briefly rather than dropping it.
            pruneDeliveredLocked()
            delivered.append(Delivered(route: route, redirect: redirect, receivedAt: Date()))
        }
        lock.unlock()

        // Bring Anchor forward — the teacher's attention is in the browser, and
        // the flow finishes back here. Hopped onto the main queue rather than
        // called inline: this method is nonisolated so an OAuth actor can drive
        // it, and NSApp is not.
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }

        guard let match else {
            AnchorDiag.log("oauth: redirect for \(route) arrived before its flow was waiting")
            return true
        }

        match.value.continuation.resume(with: Self.validate(redirect, state: match.value.state))
        return true
    }

    // MARK: Helpers

    private func resume(id: UUID, with result: Result<OAuthRedirect, Error>) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: id)
        lock.unlock()
        waiter?.continuation.resume(with: result)
    }

    /// The state check, in one place: a redirect carrying anything other than
    /// the value Anchor sent did not come from the request Anchor made, and its
    /// code is never exchanged. An error response is passed through so the flow
    /// can tell "the teacher declined" from "something is wrong".
    private static func validate(
        _ redirect: OAuthRedirect,
        state: String
    ) -> Result<OAuthRedirect, Error> {
        guard redirect.state == state else { return .failure(OAuthRedirectError.stateMismatch) }
        return .success(redirect)
    }

    /// Caller must hold `lock`.
    private func claimDeliveredLocked(route: String) -> OAuthRedirect? {
        pruneDeliveredLocked()
        guard let index = delivered.firstIndex(where: { $0.route == route }) else { return nil }
        return delivered.remove(at: index).redirect
    }

    /// Caller must hold `lock`.
    private func pruneDeliveredLocked() {
        let cutoff = Date().addingTimeInterval(-Self.deliveryGrace)
        delivered.removeAll { $0.receivedAt < cutoff }
    }

    /// `/oauth/zoom`, `oauth/zoom` and `oauth//zoom` all name the same route.
    private static func normalize(route: String) -> String {
        route
            .split(separator: "/")
            .map { $0.lowercased() }
            .joined(separator: "/")
    }
}

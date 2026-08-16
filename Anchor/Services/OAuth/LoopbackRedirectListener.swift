//
//  LoopbackRedirectListener.swift
//  Anchor
//
//  One-shot HTTP listener on 127.0.0.1 for an OAuth redirect.
//
//  Two redirect transports exist in Anchor, and neither is a stylistic choice:
//
//    - Google refuses custom URI schemes for Desktop OAuth clients. Loopback is
//      the only redirect it will register, so Classroom sign-in lands here.
//    - Zoom matches its registered redirect URL exactly, port included, so a
//      kernel-assigned port cannot work there. Zoom uses `anchor://` instead
//      (see URLSchemeHandler), and falls back to this listener on a *fixed*
//      port when a deployment registers a loopback URL instead.
//
//  A plain POSIX socket rather than `NWListener`. Network framework publishes
//  its assigned port asynchronously, only once the listener reaches `.ready`,
//  and pinning `requiredLocalEndpoint` to `127.0.0.1:.any` stops it publishing
//  one at all — which failed here as "could not determine the local redirect
//  port" before a browser ever opened. `bind(:0)` + `getsockname` hands back the
//  port synchronously, which is exactly the guarantee this flow needs: the port
//  has to be known *before* the authorization URL is built.
//
//  Binding to 127.0.0.1 specifically (not INADDR_ANY) keeps it unreachable from
//  off-machine.
//

import Foundation

nonisolated final class LoopbackRedirectListener: @unchecked Sendable {

    private let socketFD: Int32
    private let queue = DispatchQueue(label: "com.anchor.oauth.loopback")
    private var continuation: CheckedContinuation<OAuthRedirect, Error>?
    private var expectedState: String?
    private var hasResumed = false
    private var isClosed = false
    private let lock = NSLock()

    /// The port the redirect must come back on.
    let port: UInt16

    /// - Parameter preferredPort: bind this exact port, for a provider that
    ///   requires the redirect URL to match character for character. `nil` lets
    ///   the kernel choose, which is what Google's "any port on loopback" rule
    ///   allows and what avoids collisions with anything already listening.
    init(preferredPort: UInt16? = nil) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw OAuthRedirectError.listenerFailed(
                "Could not open a local socket for the sign-in redirect."
            )
        }

        // So a redirect port from a previous attempt in TIME_WAIT doesn't block us.
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = (preferredPort ?? 0).bigEndian   // 0 = let the kernel choose
        address.sin_addr.s_addr = inet_addr("127.0.0.1")    // loopback only

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            let detail = preferredPort.map { "port \($0) is in use" } ?? "errno \(errno)"
            throw OAuthRedirectError.listenerFailed(
                "Could not bind a local port for the sign-in redirect (\(detail))."
            )
        }

        // Read back whichever port the kernel assigned — synchronously, which is
        // the whole reason for using a raw socket here.
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0, bound.sin_port != 0 else {
            close(fd)
            throw OAuthRedirectError.listenerFailed("Could not determine the local redirect port.")
        }

        guard listen(fd, 1) == 0 else {
            close(fd)
            throw OAuthRedirectError.listenerFailed("Could not listen on the local redirect port.")
        }

        socketFD = fd
        port = UInt16(bigEndian: bound.sin_port)
    }

    /// `expectedState` is the CSRF value from the authorization request. It is
    /// checked here as well as by the caller so the page the browser renders
    /// tells the truth — previously a mismatched state still produced "Anchor is
    /// connected" in the tab while the app rejected the response behind it.
    func waitForRedirect(expectedState: String, timeout: TimeInterval = 300) async throws -> OAuthRedirect {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.expectedState = expectedState

            queue.async { [weak self] in self?.acceptOnce() }

            // Don't hang forever if the teacher closes the browser tab. Closing
            // the socket unblocks the accept() above.
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(with: .failure(OAuthRedirectError.cancelled))
            }
        }
    }

    /// Blocks on one connection, reads the request line, replies, and finishes.
    private func acceptOnce() {
        let client = accept(socketFD, nil, nil)
        guard client >= 0 else {
            // Socket closed by the timeout path, or a genuine failure.
            finish(with: .failure(OAuthRedirectError.cancelled))
            return
        }
        defer { close(client) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = recv(client, &buffer, buffer.count, 0)
        let request = bytesRead > 0
            ? String(decoding: buffer[0..<bytesRead], as: UTF8.self)
            : ""

        let redirect = Self.parse(request: request)

        lock.lock()
        let expected = expectedState
        lock.unlock()

        let succeeded = redirect.error == nil
            && redirect.code != nil
            && redirect.state == expected

        let body = Self.responseHTML(succeeded: succeeded)
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        _ = Array(response.utf8).withUnsafeBufferPointer { pointer in
            send(client, pointer.baseAddress, pointer.count, 0)
        }

        guard succeeded || redirect.error != nil else {
            finish(with: .failure(OAuthRedirectError.stateMismatch))
            return
        }
        finish(with: .success(redirect))
    }

    private static func parse(request: String) -> OAuthRedirect {
        // "GET /?code=…&state=… HTTP/1.1"
        guard let line = request.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://127.0.0.1\(path)")
        else {
            return OAuthRedirect(code: nil, state: nil, error: "malformed_redirect")
        }
        return OAuthRedirect.parse(components)
    }

    private static func responseHTML(succeeded: Bool) -> String {
        let heading = succeeded ? "Anchor is connected" : "Sign-in didn't complete"
        let detail = succeeded
            ? "You can close this tab and go back to Anchor."
            : "Go back to Anchor and try connecting again."
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(heading)</title>
        <style>body{font-family:-apple-system,system-ui,sans-serif;display:flex;
        align-items:center;justify-content:center;height:100vh;margin:0;
        background:#f5f5f7;color:#1d1d1f}div{text-align:center}
        h1{font-size:20px;margin:0 0 8px}p{color:#6e6e73;margin:0}</style></head>
        <body><div><h1>\(heading)</h1><p>\(detail)</p></div></body></html>
        """
    }

    /// Resumes the continuation exactly once, whichever of the response, the
    /// timeout or a failure arrives first.
    private func finish(with result: Result<OAuthRedirect, Error>) {
        lock.lock()
        guard !hasResumed, let continuation else {
            lock.unlock()
            return
        }
        hasResumed = true
        self.continuation = nil
        closeSocketLocked()
        lock.unlock()

        // Resumed outside the lock: the continuation runs arbitrary caller code.
        continuation.resume(with: result)
    }

    /// Caller must hold `lock`.
    private func closeSocketLocked() {
        guard !isClosed else { return }
        isClosed = true
        close(socketFD)
    }

    deinit {
        lock.lock()
        closeSocketLocked()
        lock.unlock()
    }
}

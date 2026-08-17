//
//  ZoomRedirectTransportTests.swift
//  AnchorTests
//
//  The leg of Zoom sign-in that had never been run end to end.
//
//  Zoom will not honour an `http://` numeric-loopback redirect, so the shipped
//  transport is `.hostedBounce`: Zoom redirects the browser to an HTTPS page we
//  host, and that page hands the query string on to `LoopbackRedirectListener`
//  on a fixed port. The HTTPS half is a static file and is either deployed or
//  it isn't. The half that can actually be wrong in interesting ways is the
//  local one — a real socket, a real HTTP request, a state check, and a page
//  rendered back into the teacher's browser — and it is the half no test
//  touched.
//
//  So these drive it the way the bounce page does: bind the listener, open a
//  TCP connection to it, write a GET, and read what comes back. A raw socket
//  rather than URLSession deliberately — the transport under test is plain HTTP
//  on loopback, and going through URLSession would put App Transport Security
//  between the test and the thing it is testing.
//
//  What these cannot cover is anything on Zoom's side of the browser: whether
//  the Marketplace app's registered redirect URL matches
//  `ZoomOAuthConfig.bounceURL` character for character. That is the single most
//  likely way this flow breaks, it is a console setting rather than code, and
//  the only way to know is to run the real sign-in once.
//

import XCTest
@testable import Anchor

// MARK: - A browser, approximately

/// Connects to 127.0.0.1 and performs one HTTP GET, exactly as the bounce page
/// causes the browser to. Returns the raw response so the tests can assert on
/// the page the teacher is actually shown, not merely on the value the flow
/// resumed with — the two have disagreed before.
private enum LoopbackClient {

    enum Failure: Error {
        case socket(String)
    }

    static func get(port: UInt16, path: String, timeout: TimeInterval = 10) throws -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket("could not open a client socket") }
        defer { close(fd) }

        // Bounded so a regression that never answers fails this test rather than
        // hanging the whole suite.
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw Failure.socket("connect failed, errno \(errno)") }

        let request = """
        GET \(path) HTTP/1.1\r
        Host: 127.0.0.1:\(port)\r
        Connection: close\r
        \r

        """
        _ = Array(request.utf8).withUnsafeBufferPointer { pointer in
            send(fd, pointer.baseAddress, pointer.count, 0)
        }

        var response = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let received = recv(fd, &buffer, buffer.count, 0)
            if received <= 0 { break }
            response += String(decoding: buffer[0..<received], as: UTF8.self)
        }
        return response
    }
}

// MARK: - The loopback leg

final class LoopbackRedirectListenerTests: XCTestCase {

    /// The listener binds and listens in `init`, so a connection that arrives
    /// before `waitForRedirect` runs sits in the accept backlog rather than
    /// being refused. That is what makes this ordering safe to write.
    private func makeListener() throws -> LoopbackRedirectListener {
        try LoopbackRedirectListener()
    }

    func testTheBouncePageQueryStringArrivesAsACodeAndState() async throws {
        // The happy path, and the one that had never been executed: the exact
        // shape the bounce page produces — the query string Zoom sent, replayed
        // verbatim at the local listener.
        let listener = try makeListener()
        let port = listener.port

        async let redirect = listener.waitForRedirect(expectedState: "state-abc", timeout: 10)
        let page = try LoopbackClient.get(port: port, path: "/oauth/zoom?code=auth-code-123&state=state-abc")
        let result = try await redirect

        XCTAssertEqual(result.code, "auth-code-123")
        XCTAssertEqual(result.state, "state-abc")
        XCTAssertNil(result.error)
        XCTAssertTrue(page.contains("Anchor is connected"), "The teacher has to be told it worked")
    }

    func testAMismatchedStateIsRejectedAndTheBrowserIsToldTheTruth() async throws {
        // Both halves matter, and the second is why the listener checks state at
        // all rather than leaving it to the caller: a mismatch used to render
        // "Anchor is connected" in the tab while the app rejected the response
        // behind it, so the teacher's screen and the app disagreed about whether
        // they were signed in.
        let listener = try makeListener()
        let port = listener.port

        async let redirect = listener.waitForRedirect(expectedState: "state-abc", timeout: 10)
        let page = try LoopbackClient.get(port: port, path: "/oauth/zoom?code=auth-code-123&state=not-the-one")

        do {
            _ = try await redirect
            XCTFail("A redirect carrying someone else's state must not resolve")
        } catch let error as OAuthRedirectError {
            XCTAssertEqual(error, .stateMismatch)
        }

        XCTAssertTrue(page.contains("Sign-in didn't complete"))
        XCTAssertFalse(page.contains("Anchor is connected"))
    }

    func testARedirectWithNoCodeIsNamedAsSuchRatherThanAsAStateMismatch() async throws {
        // The state matched, so nothing about this is a CSRF problem — Zoom just
        // didn't send a code. Reporting it as a state mismatch sent whoever was
        // debugging it looking for the wrong fault entirely, which matters here
        // because the likeliest real cause is a redirect URL that doesn't match
        // the Marketplace registration.
        let listener = try makeListener()
        let port = listener.port

        async let redirect = listener.waitForRedirect(expectedState: "state-abc", timeout: 10)
        _ = try LoopbackClient.get(port: port, path: "/oauth/zoom?state=state-abc")

        do {
            _ = try await redirect
            XCTFail("A redirect with no code cannot succeed")
        } catch let error as OAuthRedirectError {
            XCTAssertEqual(error, .missingCode)
        }
    }

    func testAStateMismatchOutranksAMissingCode() async throws {
        // Neither is present. The state failure is the one worth reporting: it
        // says the response did not come from the request Anchor made, which is
        // a different and more serious statement than "the response was
        // incomplete".
        let listener = try makeListener()
        let port = listener.port

        async let redirect = listener.waitForRedirect(expectedState: "state-abc", timeout: 10)
        _ = try LoopbackClient.get(port: port, path: "/oauth/zoom?state=not-the-one")

        do {
            _ = try await redirect
            XCTFail("Neither a code nor a matching state can succeed")
        } catch let error as OAuthRedirectError {
            XCTAssertEqual(error, .stateMismatch)
        }
    }

    func testATeacherDecliningIsPassedThroughRatherThanFailingTheTransport() async throws {
        // An error response carries no code, so there is nothing to exchange and
        // nothing at risk in surfacing it. Passing it through is what lets
        // `authorize` tell "the teacher pressed Decline" from "something is
        // broken" — one of those is not a bug report.
        let listener = try makeListener()
        let port = listener.port

        async let redirect = listener.waitForRedirect(expectedState: "state-abc", timeout: 10)
        let page = try LoopbackClient.get(
            port: port,
            path: "/oauth/zoom?error=user_denied&error_description=User%20denied%20access&state=state-abc"
        )
        let result = try await redirect

        XCTAssertEqual(result.error, "user_denied")
        XCTAssertTrue(result.isUserDenial)
        XCTAssertEqual(result.failureMessage, "User denied access")
        XCTAssertTrue(page.contains("Sign-in didn't complete"))
    }

    func testTheFixedPortIsActuallyClaimedAndReported() throws {
        // Zoom matches its registered redirect URL character for character, port
        // included, so this transport cannot accept a kernel-assigned port the
        // way Google's can. Binding the requested port and reporting it back is
        // the whole contract.
        let listener = try LoopbackRedirectListener(preferredPort: 51_991)

        XCTAssertEqual(listener.port, 51_991)
    }

    func testASecondListenerOnTheSamePortFailsLoudly() throws {
        // The failure a teacher hits when a previous sign-in never finished and
        // its listener is still up. It has to surface as an error rather than
        // silently binding somewhere else — a listener on the wrong port would
        // leave the bounce page posting into a void, and the sign-in would hang
        // with nothing to explain it.
        let first = try LoopbackRedirectListener(preferredPort: 51_992)
        XCTAssertEqual(first.port, 51_992)

        XCTAssertThrowsError(try LoopbackRedirectListener(preferredPort: 51_992)) { error in
            guard case OAuthRedirectError.listenerFailed(let detail) = error else {
                return XCTFail("Expected a listenerFailed, got \(error)")
            }
            XCTAssertTrue(detail.contains("in use"), "The message has to say why: \(detail)")
        }
    }

    func testAGarbledRequestIsRejectedRatherThanParsedIntoNonsense() async throws {
        // Anything can connect to a loopback port. A request that isn't the
        // redirect must not resolve the flow with a half-parsed value.
        let listener = try makeListener()
        let port = listener.port

        async let redirect = listener.waitForRedirect(expectedState: "state-abc", timeout: 10)
        _ = try LoopbackClient.get(port: port, path: "/favicon.ico")

        do {
            _ = try await redirect
            XCTFail("A request carrying no OAuth parameters cannot complete a sign-in")
        } catch let error as OAuthRedirectError {
            XCTAssertEqual(error, .stateMismatch, "No state at all is not the state we sent")
        }
    }
}

// MARK: - Constants that live in two files

final class ZoomBouncePageContractTests: XCTestCase {

    /// The bounce page is a static file served from another origin, so nothing
    /// at build time links it to the app. These read it off disk instead.
    private func bouncePageSource() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AnchorTests
            .deletingLastPathComponent()   // repo root
        let page = repoRoot.appendingPathComponent("Web/oauth-zoom-bounce.html")
        return try String(contentsOf: page, encoding: .utf8)
    }

    func testTheBouncePageForwardsToThePortTheListenerBinds() throws {
        // The one constant in this flow that is duplicated across a language
        // boundary. The page hardcodes the port because it is static and cannot
        // read Swift; if `loopbackPort` is ever changed without editing the page
        // to match, Zoom sign-in breaks in the least debuggable way available —
        // the browser reports success, the page forwards to a port nobody is
        // listening on, and Anchor simply waits out its five-minute timeout with
        // nothing to show for it.
        let source = try bouncePageSource()
        let expected = "http://127.0.0.1:\(ZoomOAuthConfig.loopbackPort)/\(ZoomOAuthConfig.redirectRoute)"

        XCTAssertTrue(
            source.contains(expected),
            "The bounce page must forward to \(expected)"
        )
    }

    func testTheBouncePageIsRegisteredAtTheURLTheAppSends() throws {
        // `bounceURL` is what Anchor puts in `redirect_uri` and what has to be
        // registered on the Marketplace app. The page names its own deploy
        // target in its header comment; if the two drift, the string Anchor
        // sends and the page a teacher lands on stop being the same place.
        let source = try bouncePageSource()

        XCTAssertTrue(
            source.contains(ZoomOAuthConfig.bounceURL),
            "The bounce page must document the URL it is deployed at (\(ZoomOAuthConfig.bounceURL))"
        )
    }
}

// MARK: - The custom-scheme transport

/// Not what Anchor ships for Zoom — Zoom's user-managed OAuth apps reject custom
/// URI schemes outright — but live code reachable through `.customScheme`, and
/// meant to be interchangeable with the loopback listener behind one `wait`.
/// These pin that the two agree about what counts as a failure, which they did
/// not: the loopback path passed provider errors through while this one turned
/// a denial that omitted `state` into a state mismatch.
final class URLSchemeRedirectTests: XCTestCase {

    /// A distinct route per test — `URLSchemeHandler.shared` is a singleton and
    /// parks unclaimed redirects, so tests sharing a route would collect each
    /// other's leftovers.
    private func route(_ name: String = #function) -> String {
        "oauth/test-\(abs(name.hashValue))"
    }

    func testARedirectIsDeliveredToTheFlowWaitingForIt() async throws {
        let route = route()
        let handler = URLSchemeHandler.shared

        async let redirect = handler.waitForRedirect(route: route, state: "state-abc", timeout: 10)
        // Give the waiter a moment to register before the URL arrives; the
        // opposite ordering is covered separately below.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(handler.handle(URL(string: "anchor://\(route)?code=abc&state=state-abc")!))

        let result = try await redirect
        XCTAssertEqual(result.code, "abc")
    }

    func testARedirectThatBeatsItsFlowIsNotLost() async throws {
        // The browser can come back faster than the calling flow reaches its own
        // suspension point, so an unclaimed redirect is parked briefly rather
        // than dropped.
        let route = route()
        let handler = URLSchemeHandler.shared

        XCTAssertTrue(handler.handle(URL(string: "anchor://\(route)?code=early&state=state-abc")!))

        let result = try await handler.waitForRedirect(route: route, state: "state-abc", timeout: 10)
        XCTAssertEqual(result.code, "early")
    }

    func testADenialWithoutAnEchoedStateStillReadsAsADenial() async throws {
        // The divergence this class exists for. There is no code in an error
        // response, so nothing can be exchanged and nothing is at risk in
        // passing it through — and reporting a teacher who pressed Decline as
        // "the response didn't match the request Anchor sent" sends them to
        // support over a button they meant to press.
        let route = route()
        let handler = URLSchemeHandler.shared

        XCTAssertTrue(handler.handle(URL(string: "anchor://\(route)?error=user_denied")!))

        let result = try await handler.waitForRedirect(route: route, state: "state-abc", timeout: 10)
        XCTAssertEqual(result.error, "user_denied")
        XCTAssertTrue(result.isUserDenial)
    }

    func testAMismatchedStateOnASuccessIsStillRejected() async throws {
        // The check that actually matters is the one guarding a success, and
        // relaxing the error path must not have relaxed this one too.
        let route = route()
        let handler = URLSchemeHandler.shared

        XCTAssertTrue(handler.handle(URL(string: "anchor://\(route)?code=abc&state=not-the-one")!))

        do {
            _ = try await handler.waitForRedirect(route: route, state: "state-abc", timeout: 10)
            XCTFail("A code arriving with the wrong state must never be exchanged")
        } catch let error as OAuthRedirectError {
            XCTAssertEqual(error, .stateMismatch)
        }
    }

    func testTheRouteIsMatchedRegardlessOfHowItIsSpelled() async throws {
        // `anchor://oauth/zoom` parses as host "oauth" plus path "/zoom", so the
        // route has to be rebuilt from both halves and compared case- and
        // slash-insensitively. A provider that normalises the URL differently
        // must still find its waiter.
        let handler = URLSchemeHandler.shared

        XCTAssertTrue(handler.handle(URL(string: "anchor://OAuth/Spelling?code=abc&state=state-abc")!))

        let result = try await handler.waitForRedirect(
            route: "/oauth/spelling",
            state: "state-abc",
            timeout: 10
        )
        XCTAssertEqual(result.code, "abc")
    }

    func testTheRedirectURIIsTheStringPastedIntoTheConsole() {
        // Exact-match registration, so this string is a contract with the
        // provider rather than a detail.
        XCTAssertEqual(URLSchemeHandler.redirectURI(route: "oauth/zoom"), "anchor://oauth/zoom")
        XCTAssertEqual(URLSchemeHandler.redirectURI(route: "/oauth/zoom"), "anchor://oauth/zoom")
    }
}

//
//  MeetingSDKRemoteSignerTests.swift
//  AnchorTests
//
//  The server-signing path, and the rule that decides between it and local
//  signing.
//
//  ── Why this path exists ────────────────────────────────────────────────────
//
//  The Meeting SDK secret is an HS256 signing key, so shipping it in the binary
//  would let anyone who extracts it mint tokens as Anchor (ship-checklist §3).
//  That kept the bot exclusive to per-school deployments, where an admin
//  provisions the secret by hand — and since the participant REST scopes need
//  the *teacher's own* account to be Business or Education, a lone teacher had
//  no live-signal source at all. Signing on the server is the way out.
//
//  ── The case this file is really written for ────────────────────────────────
//
//  `testLocalSecretWinsOverRemote`. A school that registered its own Meeting
//  SDK app must keep authenticating as *their* app. If `resolvedToken` ever
//  preferred the remote signer, their bot would silently authenticate as
//  Anchor's app instead — it would still work, which is what makes it
//  dangerous, and it is the same substitution shape as the school-id canary
//  that printed Anchor's public client where a school's own id belonged.
//

import XCTest
@testable import Anchor

// MARK: - Stub transport

/// Answers every request from a queue, and records what was asked.
///
/// Registered per-session rather than globally so a test that expects *no*
/// network can prove it: `requests` staying empty is the assertion.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (status: Int, body: Data)?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        response = nil
        requests = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let stub = Self.response ?? (200, Data())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class MeetingSDKRemoteSignerTests: XCTestCase {

    private let endpoint = URL(string: "https://anchorteach.vercel.app/api/zoom/sdk-token")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func signer(zoomToken: String = "zoom-access-token") -> MeetingSDKRemoteSigner {
        MeetingSDKRemoteSigner(endpoint: endpoint, zoomAccessToken: { zoomToken })
    }

    // MARK: - Which source is used

    func testLocalSecretWinsOverRemote() async throws {
        // Both available. Local must be used, and the network must not be
        // touched at all — see the file comment for why this is the case that
        // matters most.
        StubURLProtocol.response = (200, #"{"token":"token-from-server"}"#.data(using: .utf8)!)

        let provider = MeetingSDKTokenProvider(
            sdkKey: "LOCALKEY",
            sdkSecret: "localsecret",
            remote: signer()
        )
        let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let resolved = try await provider.resolvedToken(
            issuedAt: issuedAt,
            session: StubURLProtocol.session()
        )

        XCTAssertEqual(resolved, try provider.token(issuedAt: issuedAt))
        XCTAssertNotEqual(resolved, "token-from-server")
        XCTAssertTrue(
            StubURLProtocol.requests.isEmpty,
            "a provisioned school must never reach Anchor's signing endpoint"
        )
    }

    func testRemoteUsedWhenNoLocalSecret() async throws {
        StubURLProtocol.response = (200, #"{"token":"token-from-server"}"#.data(using: .utf8)!)

        let provider = MeetingSDKTokenProvider(sdkKey: "", sdkSecret: "", remote: signer())
        let resolved = try await provider.resolvedToken(session: StubURLProtocol.session())

        XCTAssertEqual(resolved, "token-from-server")
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testNoSecretAndNoRemoteStillReportsMissingCredentials() async {
        // The per-school install that was never provisioned. It must keep
        // naming the missing credential rather than failing inside the SDK.
        let provider = MeetingSDKTokenProvider(sdkKey: "", sdkSecret: "")

        do {
            _ = try await provider.resolvedToken(session: StubURLProtocol.session())
            XCTFail("expected missingSDKCredentials")
        } catch let error as ZoomError {
            XCTAssertEqual(error, .missingSDKCredentials)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - The request itself

    func testRequestCarriesZoomBearerTokenAndPosts() async throws {
        StubURLProtocol.response = (200, #"{"token":"t"}"#.data(using: .utf8)!)

        _ = try await signer(zoomToken: "the-teachers-zoom-token")
            .token(session: StubURLProtocol.session())

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer the-teachers-zoom-token"
        )
    }

    func testNoMeetingNumberOrStudentDataIsSent() async throws {
        // The native SDK token authenticates the app, not a meeting, so the
        // request body carries nothing. Pinned because "send the meeting
        // number too" is the obvious-looking edit, and it would put class
        // identifiers on the wire for no reason.
        StubURLProtocol.response = (200, #"{"token":"t"}"#.data(using: .utf8)!)

        _ = try await signer().token(session: StubURLProtocol.session())

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
    }

    // MARK: - Server failures reach the teacher

    func testServerMessageIsPassedThroughOnFailure() async {
        // 503 is the unconfigured deployment. The server already phrases these
        // for a teacher, so the app must not replace them with a generic one.
        StubURLProtocol.response = (
            503,
            #"{"error":"Anchor's meeting bot is not configured on this server."}"#.data(using: .utf8)!
        )

        do {
            _ = try await signer().token(session: StubURLProtocol.session())
            XCTFail("expected a failure")
        } catch let error as ZoomError {
            XCTAssertEqual(
                error.errorDescription,
                "Anchor's meeting bot is not configured on this server."
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testExpiredZoomGrantTellsTheTeacherToReconnect() async {
        StubURLProtocol.response = (
            401,
            #"{"error":"That Zoom sign-in is no longer valid. Reconnect Zoom and try again."}"#
                .data(using: .utf8)!
        )

        do {
            _ = try await signer().token(session: StubURLProtocol.session())
            XCTFail("expected a failure")
        } catch let error as ZoomError {
            XCTAssertEqual(
                error.errorDescription,
                "That Zoom sign-in is no longer valid. Reconnect Zoom and try again."
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testEmptyTokenIsRefusedRatherThanReturned() async {
        // A 200 carrying nothing usable must not become an empty SDK token —
        // that fails several steps later inside sdkAuth, which reads as a wrong
        // secret rather than an absent one.
        StubURLProtocol.response = (200, #"{"token":""}"#.data(using: .utf8)!)

        do {
            _ = try await signer().token(session: StubURLProtocol.session())
            XCTFail("expected a failure")
        } catch let error as ZoomError {
            XCTAssertEqual(error.errorDescription, "Anchor's meeting service returned no token.")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMalformedBodyIsRefused() async {
        StubURLProtocol.response = (200, Data("not json".utf8))

        do {
            _ = try await signer().token(session: StubURLProtocol.session())
            XCTFail("expected a failure")
        } catch let error as ZoomError {
            XCTAssertEqual(error.errorDescription, "Anchor's meeting service returned no token.")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Endpoint configuration

    func testDefaultEndpointIsTheProductionSiteOverHTTPS() {
        // A signing endpoint reached over plain HTTP would expose the teacher's
        // Zoom access token in transit.
        XCTAssertEqual(ZoomConfig.meetingSDKTokenURL.scheme, "https")
        XCTAssertEqual(ZoomConfig.meetingSDKTokenURL.path, "/api/zoom/sdk-token")
    }
}

//
//  PKCE.swift
//  Anchor
//
//  Proof Key for Code Exchange (RFC 7636), shared by the Google and Zoom flows.
//
//  Why it is here at all: a desktop app cannot keep a secret. Anything shipped
//  in the bundle is readable, so the client secret cannot be what proves the
//  token request came from Anchor. PKCE puts that proof in a random verifier
//  generated per sign-in, kept in this process, and never sent to the browser —
//  only its SHA-256 hash travels in the authorization URL. A code intercepted
//  on the way back is useless without the verifier.
//

import CryptoKit
import Foundation

nonisolated enum PKCE {

    /// One sign-in's verifier: 32 random bytes, base64url encoded.
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    /// The S256 challenge for `verifier`.
    static func makeCodeChallenge(from verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    /// A CSRF `state` value. Same generator as the verifier — both just need to
    /// be unguessable and single-use.
    static func makeState() -> String {
        makeCodeVerifier()
    }
}

extension Data {
    /// base64url without padding, as PKCE requires.
    nonisolated var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

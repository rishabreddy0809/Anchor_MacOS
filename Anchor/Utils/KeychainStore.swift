//
//  KeychainStore.swift
//  Anchor
//
//  Thin wrapper over the macOS Keychain. Anchor's Zoom Client Secret is written
//  here and nowhere else — never to UserDefaults, a plist, or source.
//

import Combine
import Foundation
import Security

nonisolated struct KeychainStore: Sendable {

    enum KeychainError: LocalizedError, Equatable {
        case unexpectedStatus(OSStatus)
        case dataCorrupted

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return "Keychain error \(status)\(message.map { ": \($0)" } ?? "")"
            case .dataCorrupted:
                return "The saved credentials could not be read."
            }
        }
    }

    let service: String

    // MARK: - CRUD

    func save(_ data: Data, account: String) throws {
        // Try update first so we don't churn the ACL on every save.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.dataCorrupted }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - Credentials

nonisolated struct ZoomCredentials: Codable, Equatable, Sendable {
    var accountID: String
    var clientID: String
    var clientSecret: String
    /// Meeting SDK credentials — a *separate* app type in the Zoom Marketplace
    /// from the Server-to-Server OAuth app above. Only needed for the bot.
    var sdkKey: String?
    var sdkSecret: String?

    var isComplete: Bool {
        !accountID.trimmed.isEmpty && !clientID.trimmed.isEmpty && !clientSecret.trimmed.isEmpty
    }

    var trimmedCopy: ZoomCredentials {
        ZoomCredentials(
            accountID: accountID.trimmed,
            clientID: clientID.trimmed,
            clientSecret: clientSecret.trimmed,
            sdkKey: sdkKey?.trimmed,
            sdkSecret: sdkSecret?.trimmed
        )
    }

    var hasSDKCredentials: Bool {
        !(sdkKey ?? "").isEmpty && !(sdkSecret ?? "").isEmpty
    }

    /// Safe to show in the UI or logs.
    var redactedSecret: String {
        guard clientSecret.count > 4 else { return "••••" }
        return String(repeating: "•", count: 8) + clientSecret.suffix(4)
    }

    /// HTTP Basic credential for the Server-to-Server OAuth token exchange.
    var basicAuthValue: String? {
        Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
    }
}

extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Loads and saves ZoomCredentials, keeping the secret in the Keychain.
final class ZoomCredentialsStore: ObservableObject {

    static let shared = ZoomCredentialsStore()

    @Published private(set) var credentials: ZoomCredentials?
    /// The bot's own Zoom account, kept separate from the teacher's.
    @Published private(set) var botCredentials: ZoomCredentials?
    @Published private(set) var lastError: String?

    private let keychain = KeychainStore(service: ZoomConfig.keychainService)
    private let account = ZoomConfig.keychainAccount
    private let botAccount = ZoomConfig.botKeychainAccount

    init() {
        load()
    }

    var hasCredentials: Bool { credentials?.isComplete == true }
    var hasBotCredentials: Bool { botCredentials?.isComplete == true }

    func load() {
        credentials = read(account: account)
        botCredentials = read(account: botAccount)
    }

    private func read(account: String) -> ZoomCredentials? {
        do {
            guard let data = try keychain.read(account: account) else { return nil }
            let decoded = try JSONDecoder().decode(ZoomCredentials.self, from: data)
            lastError = nil
            return decoded
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // The bot's credentials used to be seeded here from a hardcoded
    // BotCredentials.swift on every launch. That file is gone: it held a live
    // Client Secret and an SDK Secret in plaintext, which is the one thing this
    // store exists to avoid. The Keychain entry it seeded
    // (`ZoomConfig.botKeychainAccount`) survives and is now the only copy.
    //
    // To provision the bot on a fresh Mac, or after rotating the secret in the
    // Zoom Marketplace, call `saveBot(_:)` with the new values — from a one-off
    // debug action or a Settings field. Do not reintroduce a source-level seed.

    @discardableResult
    func save(_ new: ZoomCredentials) -> Bool {
        write(new, to: account) { [weak self] in self?.credentials = $0 }
    }

    @discardableResult
    func saveBot(_ new: ZoomCredentials) -> Bool {
        write(new, to: botAccount) { [weak self] in self?.botCredentials = $0 }
    }

    private func write(
        _ new: ZoomCredentials,
        to account: String,
        assign: (ZoomCredentials) -> Void
    ) -> Bool {
        let cleaned = new.trimmedCopy
        do {
            let data = try JSONEncoder().encode(cleaned)
            try keychain.save(data, account: account)
            assign(cleaned)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func clear() {
        do {
            try keychain.delete(account: account)
            credentials = nil
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Snapshots for the auth actors, which run off the main actor.
    func snapshot() -> ZoomCredentials? { credentials }
    func botSnapshot() -> ZoomCredentials? { botCredentials }
}

// MARK: - Meeting SDK credentials

/// The Meeting SDK Key/Secret used to sign the SDK JWT.
///
/// Deliberately separate from `ZoomCredentialsStore`. That store holds a
/// *Server-to-Server* Client ID/Secret, which authenticates an account; this
/// pair authenticates the **app** to the Meeting SDK and comes from a different
/// Marketplace app entirely. They are easy to confuse — both are a "Client
/// ID/Secret" — and swapping them makes `sdkAuth` fail locally, before any
/// network request, which looks identical to a malformed JWT.
///
/// This is app-level configuration shipped with the build, not something a
/// teacher provisions: the key defaults to `OAuthClientDefaults.meetingSDKKey`,
/// and only the secret needs to reach the Keychain once, the same way the OAuth
/// client secret does.
///
/// "App-level" means per *deployment*, not per teacher — a school running the
/// per-school route creates its own Meeting SDK app and provisions both halves
/// through `ANCHOR_ZOOM_SDK_KEY` / `_SECRET`, which `resolved()` below prefers
/// over the shipped default. See ADMIN-SETUP.md step 2.
nonisolated enum MeetingSDKCredentialStore {

    private static let service = "com.anchor.zoom.meetingsdk"
    private static let keyAccount = "sdk-key"
    private static let secretAccount = "sdk-secret"

    private static var keychain: KeychainStore { KeychainStore(service: service) }

    /// A Keychain entry wins over the shipped default, so a deployment can
    /// point at its own Meeting SDK app without a rebuild.
    static func resolved() -> (key: String, secret: String)? {
        let key = stored(keyAccount)
            ?? OAuthClientDefaults.value(OAuthClientDefaults.meetingSDKKey)
        let secret = stored(secretAccount)
            ?? OAuthClientDefaults.value(OAuthClientDefaults.meetingSDKSecret)

        guard let key, let secret else { return nil }
        return (key, secret)
    }

    /// Whether a join can even be attempted. Checked before building the bot so
    /// the failure names the missing credential instead of surfacing as an
    /// opaque SDK error four steps later.
    static var isConfigured: Bool { resolved() != nil }

    /// Passing `nil` clears that half, so provisioning can also un-provision.
    ///
    /// **Not the right entry point for environment seeding**, and that mistake
    /// is what `apply(key:secret:)` below exists to prevent: an absent
    /// environment variable arrives here as `nil` and silently deletes a
    /// provisioned value. Use this only where the caller genuinely means both
    /// halves, such as Settings → Advanced in a DEBUG build.
    static func save(key: String?, secret: String?) {
        write(key, account: keyAccount)
        write(secret, account: secretAccount)
    }

    /// Applies only the halves the caller actually asked about.
    ///
    /// `.leave` writes nothing — which is the whole point. Rotating just the
    /// secret used to arrive as `save(key: nil, secret: new)` and delete a
    /// school's provisioned key, after which `resolved()` fell back to Anchor's
    /// own shipped `meetingSDKKey` and paired it with the school's secret. That
    /// mismatch fails inside `sdkAuth` before any network request, and reports
    /// itself as a *missing* credential when both were present. See
    /// CredentialSeed.swift.
    static func apply(key: CredentialIntent, secret: CredentialIntent) {
        if key.writes { write(key.storedValue, account: keyAccount) }
        if secret.writes { write(secret.storedValue, account: secretAccount) }
    }

    private static func stored(_ account: String) -> String? {
        guard let data = (try? keychain.read(account: account)) ?? nil else { return nil }
        return OAuthClientDefaults.value(String(decoding: data, as: UTF8.self))
    }

    private static func write(_ value: String?, account: String) {
        guard let value = OAuthClientDefaults.value(value ?? "") else {
            try? keychain.delete(account: account)
            return
        }
        try? keychain.save(Data(value.utf8), account: account)
    }
}

//
//  PrivacyDisclosureTests.swift
//  AnchorTests
//
//  Pins the published privacy policy against the credential stores the app
//  actually writes to.
//
//  Why this file exists, because the gap it closes is the interesting part.
//  On 2026-08-21 the live policy's §5 "Where the data lives" enumerated four
//  storage locations and named exactly one Keychain entry — "Your Google
//  refresh token". Anchor has written the *teacher's Zoom grant* to the
//  Keychain since the OAuth work landed: `ZoomOAuthStore` encodes a
//  `ZoomOAuthTokens` — refresh token, access token, expiry, granted scopes and
//  the account label — under `com.anchor.zoom.oauth`. The policy did not say
//  so. §10 had the matching hole: it told a teacher how to disconnect and
//  revoke *Google* and said nothing about Zoom.
//
//  This is not an abstract compliance point. The Zoom Marketplace submission
//  answered **Yes** to "Collects/stores/retains Zoom user data including OAuth
//  tokens?" (recorded in `zoom-submission-remaining.md`), and a publication
//  reviewer reads that answer beside the Privacy Policy URL on the listing.
//  The two artifacts disagreed, and the public one was the wrong one.
//
//  **Why `RetentionPolicyTests` did not catch it, which is the reusable
//  lesson.** That test already reads this exact file — it is not a case of an
//  unguarded artifact. It reads it *for retention day-counts only*. The file
//  was covered; the section was not. This project has now recorded the same
//  shape three times: `SupportContactTests` quoted in its own header a
//  sentence that was live in a type it never scanned, `ZoomError
//  .invalidCredentials` was excluded from a scan by a predicate that was
//  itself wrong, and now a guarded file with an unguarded section. **A guard
//  is worth its list times the surfaces it enumerates, and "the file has a
//  test" answers neither factor.**
//

import XCTest

final class PrivacyDisclosureTests: XCTestCase {

    // MARK: - Locating the two artifacts

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
    }

    /// Read from source rather than the live URL, for the reason
    /// `RetentionPolicyTests` already records: a networked test fails on a
    /// plane and measures the deploy rather than the claim.
    private func privacyPolicySource() throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent("website/landing/src/routes/privacy.tsx"),
            encoding: .utf8
        )
    }

    /// Every `.swift` file under `Anchor/`, which is where a new credential
    /// store would appear.
    private func appSourceFiles() throws -> [URL] {
        let app = repoRoot.appendingPathComponent("Anchor")
        let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }

    // MARK: - What the code declares it stores

    /// Every Keychain service identifier declared anywhere in `Anchor/`.
    ///
    /// Discovered from source rather than listed here on purpose: a hard-coded
    /// list in the test is the thing that goes stale, and going stale silently
    /// is the whole defect this file exists for.
    ///
    /// **Matched on the declaration, not on the string.** The first version of
    /// this matched any `"com.anchor.…"` literal and pulled in six identifiers
    /// that have nothing to do with the Keychain — the diagnostics subsystem,
    /// the CoreML container, the loopback listener. An over-broad guard is not
    /// a safe default here: it would have had a maintainer classify
    /// `com.anchor.diag` as personal data or not, which teaches them the table
    /// is noise and is how a real entry gets waved through.
    private func keychainServicesInSource() throws -> Set<String> {
        let pattern = try NSRegularExpression(
            pattern: #"\b(?:keychainService|service)\s*=\s*"(com\.anchor\.[A-Za-z0-9._]+)""#
        )
        var found: Set<String> = []
        for file in try appSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in pattern.matches(in: source, range: range) {
                if let r = Range(match.range(at: 1), in: source) { found.insert(String(source[r])) }
            }
        }
        return found
    }

    /// How many places actually build a `KeychainStore`.
    ///
    /// This exists to catch the way the regex above can fail *quietly*: a
    /// fifth store declared as `private static let svc = "com.anchor.…"` is
    /// not matched by a pattern keyed on the name `service`, so the classified
    /// set would still equal the discovered set and the guard would pass while
    /// missing a store. Counting construction sites is independent of what the
    /// constant is called, so the two have to disagree before anything slips.
    private func keychainConstructionSiteCount() throws -> Int {
        var count = 0
        for file in try appSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            count += source.components(separatedBy: "KeychainStore(service:").count - 1
        }
        return count
    }

    /// The classification the policy is written against.
    ///
    /// `nil` means "holds per-deployment configuration, not the teacher's
    /// personal data, so the privacy policy owes the reader nothing about it" —
    /// the S2S bot credentials and the Meeting SDK key/secret are values a
    /// school administrator provisions, not anything about a person.
    /// A non-`nil` value is the word §5 must use when disclosing that store.
    ///
    /// **This table is deliberately the only hand-maintained thing here, and
    /// the test below fails on any service missing from it.** That is the
    /// point: a fifth store cannot be added without someone answering the
    /// question "is this personal data?" in writing.
    private static let classification: [String: String?] = [
        "com.anchor.google.classroom": "Google",
        "com.anchor.zoom.oauth": "Zoom",
        "com.anchor.zoom.credentials": nil,
        "com.anchor.zoom.meetingsdk": nil,
    ]

    // MARK: - The guards

    /// A new credential store must be classified before it can ship.
    ///
    /// This is the case that would have caught the original defect at the
    /// moment `ZoomOAuthStore` was introduced, rather than four days later.
    func testEveryKeychainServiceIsClassified() throws {
        let found = try keychainServicesInSource()

        XCTAssertFalse(
            found.isEmpty,
            """
            No Keychain service identifiers were found under Anchor/. Either the \
            naming convention changed or this test is now scanning nothing — a \
            guard that finds nothing passes vacuously, which is worse than failing.
            """
        )

        let unclassified = found.subtracting(Self.classification.keys)
        XCTAssertTrue(
            unclassified.isEmpty,
            """
            Keychain service(s) \(unclassified.sorted()) exist in the app but are \
            not classified in PrivacyDisclosureTests.classification. Decide whether \
            each holds the teacher's personal data. If it does, disclose it in \
            §"Where the data lives" in privacy.tsx and map it to the provider name \
            here; if it is per-deployment configuration, map it to nil and say why.
            """
        )

        // The other direction: a classified service that no longer exists means
        // the table is carrying a store that was deleted, and the next reader
        // would trust it as a description of the app.
        let vanished = Set(Self.classification.keys).subtracting(found)
        XCTAssertTrue(
            vanished.isEmpty,
            """
            Keychain service(s) \(vanished.sorted()) are classified here but no \
            longer declared in Anchor/. Remove them from the table, and check \
            whether privacy.tsx still describes a store that is gone.
            """
        )

        // And the independent count, which is what catches a store whose
        // constant is not named `service`. See keychainConstructionSiteCount().
        let sites = try keychainConstructionSiteCount()
        XCTAssertEqual(
            sites, found.count,
            """
            \(sites) place(s) construct a KeychainStore but \(found.count) service \
            identifier(s) were discovered by name. They should match one-to-one. A \
            store whose service constant is not called `service` or `keychainService` \
            is invisible to the scan above, and an undisclosed credential store is \
            exactly what this file exists to prevent.
            """
        )
    }

    /// Every store holding personal data is named in §5, next to the Keychain.
    func testStorageSectionDisclosesEveryPersonalDataStore() throws {
        let source = try privacyPolicySource()
        let section = try XCTUnwrap(
            Self.section(withID: "storage", in: source),
            "§\"Where the data lives\" (id=\"storage\") was not found in privacy.tsx."
        )

        XCTAssertTrue(
            section.contains("Keychain"),
            "§\"Where the data lives\" no longer mentions the Keychain at all."
        )

        let items = Self.listItems(in: section)
        XCTAssertFalse(items.isEmpty, "§\"Where the data lives\" no longer contains a list.")

        let present = try keychainServicesInSource()
        for (service, provider) in Self.classification {
            guard let provider, present.contains(service) else { continue }
            // Both words, in the *same* list item.
            //
            // `section.contains(provider)` is what this asserted first, and
            // planting the violation proved it vacuous: deleting the Zoom
            // disclosure entirely left the test passing, because the
            // session-history bullet in this same section says "engagement
            // scores and Zoom signals". The section is about storage and
            // mentions both providers for unrelated reasons, so only the
            // pairing carries the claim.
            XCTAssertTrue(
                items.contains { $0.contains(provider) && $0.contains("Keychain") },
                """
                The app stores the teacher's \(provider) credentials in the Keychain \
                (service \(service)), and no single item in §"Where the data lives" \
                names \(provider) and the Keychain together. A school's reviewer reads \
                this section to find out what is held on the Mac; an undisclosed \
                credential store is the one thing it must not omit.
                """
            )
        }
    }

    /// Every store holding personal data tells the reader how to revoke it.
    ///
    /// §10 enumerated Google and stopped, so a teacher had no way to learn from
    /// the policy that Anchor's Disconnect revokes at Zoom rather than merely
    /// forgetting locally — which is the more reassuring fact of the two and
    /// was the one left out.
    func testRetentionSectionTellsTheReaderHowToRevokeEachConnection() throws {
        let source = try privacyPolicySource()
        let section = try XCTUnwrap(
            Self.section(withID: "retention", in: source),
            "§\"Retention and deletion\" (id=\"retention\") was not found in privacy.tsx."
        )

        let items = Self.listItems(in: section)
        XCTAssertFalse(items.isEmpty, "§\"Retention and deletion\" no longer contains a list.")

        let present = try keychainServicesInSource()
        for (service, provider) in Self.classification {
            guard let provider, present.contains(service) else { continue }
            // Paired with "revoke" for the same reason as §5 above: this
            // section names Zoom in passing elsewhere, so the provider alone
            // does not establish that the reader was told how to end the
            // connection.
            XCTAssertTrue(
                items.contains { $0.contains(provider) && $0.contains("revoke") },
                """
                §"Retention and deletion" has no item telling the reader how to revoke \
                the \(provider) connection, though the app stores \(provider) \
                credentials (service \(service)). This section is a list, and a list \
                that names one provider and not the other reads as though only one can \
                be revoked.
                """
            )
        }
    }

    // MARK: - Section extraction

    /// The text of one `<LegalSectionBody id="…">` block, up to the next one.
    ///
    /// Slicing by section rather than searching the whole file is the entire
    /// point of this file: `contains("Zoom")` over all of `privacy.tsx` passes
    /// trivially — the document is largely about Zoom — and would have passed
    /// against the unfixed page. The assertion has to be scoped to the section
    /// that owes the reader the answer.
    /// The `<li>` items inside a section, as raw JSX text.
    ///
    /// Crude on purpose — this is matching prose, not parsing JSX, and the
    /// assertions only ask whether two words occur in the same bullet.
    private static func listItems(in section: String) -> [String] {
        section.components(separatedBy: "<li>").dropFirst().map {
            String($0.components(separatedBy: "</li>").first ?? "")
        }
    }

    private static func section(withID id: String, in source: String) -> String? {
        guard let start = source.range(of: "<LegalSectionBody id=\"\(id)\"") else { return nil }
        let rest = source[start.upperBound...]
        let end = rest.range(of: "<LegalSectionBody id=\"")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }
}

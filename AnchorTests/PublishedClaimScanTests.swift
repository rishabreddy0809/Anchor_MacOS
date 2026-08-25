//
//  PublishedClaimScanTests.swift
//  AnchorTests
//
//  Scans every published web surface for unqualified claims that Anchor holds
//  nothing, now that it holds something.
//
//  Why this file exists. Anchor gained two servers on 2026-08-25: Firebase
//  Authentication behind `AnchorAccount`, and `POST /api/zoom/sdk-token` on the
//  landing site. `9f19c1f` corrected the published copy that said otherwise,
//  and found the sentence in five places — `privacy.tsx`, `pilot-terms.tsx`,
//  `index.tsx`, `Faq.tsx`, `site.ts`. It did not find it in two more, because
//  those two say it in different words:
//
//    - `pilot-terms.tsx` §"Leaving, and being asked to leave": *"there is
//      nothing on our side to delete because there was never anything there"* —
//      in the section a departing teacher reads to find out how to have their
//      account removed, which is now the one thing that section owes them.
//    - `privacy.tsx` §"Retention and deletion": *"We hold nothing, so there is
//      nothing for us to delete"* — contradicted one section later by
//      §"Your rights", which correctly names *"the two things we do hold"*.
//      The document disagreed with itself across two adjacent sections.
//
//  Both were found on 2026-08-25 by reading the deployed pages after the fix
//  shipped, which is this project's standing method, and neither was caught by
//  a search for the phrase that was corrected. That is the failure this file
//  exists to make structural rather than repeated: a blocklist of the exact
//  wrong sentence catches the sentence, and the next writer phrases it their
//  own way.
//
//  **So the rule is a shape, not a phrase.** A sentence that says Anchor holds,
//  stores or receives nothing must say nothing *of what* — students, classes,
//  rosters, scores. The unscoped version is now false, and it is false in the
//  direction that is hardest to defend: a school's reviewer reads it as a
//  promise, and it is a promise Anchor no longer keeps.
//
//  **And the second factor, which is the half this project keeps getting
//  wrong.** `PrivacyDisclosureTests` already reads `privacy.tsx`, and its own
//  header records that a guard is worth its list times the surfaces it
//  enumerates. It reads one file. `SupportContactTests` enumerates two error
//  types. `TeacherFacingCopyTests` reads `Anchor/Views`. Every one of them was
//  written after a defect escaped through the surfaces factor, and this one
//  escaped through it again. So this scan takes the whole directory and skips
//  nothing by name — a per-file exemption is the hole, as
//  `TeacherFacingSourceScanTests` already records about its own first version.
//

import XCTest

final class PublishedClaimScanTests: XCTestCase {

    // MARK: - The rule

    /// Sentence fragments that assert Anchor holds nothing.
    ///
    /// Each one of these was live and wrong at some point on 2026-08-25, which
    /// is the bar for being on this list: a phrasing somebody actually reached
    /// for, not a phrasing somebody might.
    private static let absoluteNegations = [
        "hold nothing",
        "holds nothing",
        "held nothing",
        "nothing for us to delete",
        "nothing on our side",
        "never anything there",
        "no server",
        "no backend",
        "no account system",
        "no accounts",
        "no database",
    ]

    /// Words that scope such a claim to the thing it is still true of.
    ///
    /// Anchor genuinely receives nothing about a class. It receives an email
    /// address and a name. A sentence that names what it is talking about is
    /// therefore fine, and a sentence that does not is a promise about
    /// everything.
    private static let scopingWords = [
        "student",
        "class",          // covers "classes" and "classroom"
        "roster",
        "score",
        "transcript",
        "grade",
        "lesson",
        "coursework",
    ]

    // MARK: - The scan

    func testNoPublishedSurfaceClaimsAnchorHoldsNothing() throws {
        let surfaces = try publishedSurfaces()

        // The plant-that-fires-nothing trap, made impossible to hit silently.
        // A sweep that matched no files would pass this test forever and look
        // exactly like a site with no violations in it.
        XCTAssertGreaterThan(
            surfaces.count, 5,
            """
            The scan found \(surfaces.count) source file(s) under website/landing/src. \
            That is too few to be the real site, so the sweep is matching nothing and \
            this guard is vacuous. Check the path before trusting a pass.
            """
        )

        var violations: [String] = []

        for surface in surfaces {
            let source = try String(contentsOf: surface, encoding: .utf8)
            for sentence in Self.publishedSentences(in: source) {
                let lower = sentence.lowercased()
                guard let trigger = Self.absoluteNegations.first(where: { lower.contains($0) })
                else { continue }
                guard !Self.scopingWords.contains(where: { lower.contains($0) }) else { continue }

                violations.append(
                    "\(surface.lastPathComponent): \"\(sentence)\"  [matched: \(trigger)]"
                )
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            \(violations.count) published sentence(s) claim Anchor holds nothing, without \
            saying nothing of what. Anchor holds an email address and a name in Firebase \
            Authentication, and runs a signing endpoint at /api/zoom/sdk-token. An \
            unscoped version of this claim is read by a school's reviewer as a promise \
            about everything, and it is one Anchor cannot keep.

            Say what is true instead: nothing about a *class* reaches us. See \
            privacy.tsx §"Your Anchor account" for the canonical wording.

            \(violations.joined(separator: "\n"))
            """
        )
    }

    /// The site tells a departing teacher how to have their account deleted.
    ///
    /// Separate from the scan above, because removing a false sentence and
    /// answering the question it used to answer are two different repairs, and
    /// the first can be done without the second. §"Leaving" said there was
    /// nothing to delete; deleting that sentence alone would leave a teacher
    /// reading the exit section with no route out.
    func testEveryExitSurfaceNamesTheAccountDeletionRoute() throws {
        let contact = "CONTACT_EMAIL"

        for (file, section) in [
            ("website/landing/src/routes/privacy.tsx", "retention"),
            ("website/landing/src/routes/pilot-terms.tsx", "leaving"),
        ] {
            let source = try String(
                contentsOf: repoRoot.appendingPathComponent(file), encoding: .utf8
            )
            let body = try XCTUnwrap(
                Self.section(withID: section, in: source),
                "§\(section) was not found in \(file)."
            )

            XCTAssertTrue(
                body.contains("account") && body.contains(contact),
                """
                §\(section) in \(file) does not name the Anchor account and a way to \
                reach us about it. This is the section a teacher reads on the way out, \
                and the account is the only thing they cannot delete themselves — \
                deleting the app does not touch it, because it does not live on \
                their Mac.
                """
            )
        }
    }

    // MARK: - Reading the surfaces

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
    }

    /// Every `.tsx` and `.ts` under `website/landing/src`.
    ///
    /// Deliberately not a list of the files that carry copy. `site.ts` is the
    /// reason: it looks like a constants file and it holds `REQUIREMENTS` and
    /// `PILOT_TERMS`, whose strings render on `/apply`. A hand-maintained list
    /// would have contained the four legal routes and missed it.
    private func publishedSurfaces() throws -> [URL] {
        let root = repoRoot.appendingPathComponent("website/landing/src")
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in walker
        where url.pathExtension == "tsx" || url.pathExtension == "ts" {
            files.append(url)
        }
        return files
    }

    // MARK: - JSX to prose

    /// Every sentence a reader can end up seeing, from both places copy hides.
    ///
    /// **Two streams, and the second one exists because a canary found it
    /// missing.** The first plant of this guard went into an attribute —
    /// `<footer data-x="Anchor has no server and no accounts.">` — and fired
    /// nothing, which this project treats as information rather than as a pass.
    /// The cause was that `prose(from:)` strips `<[^>]+>` wholesale, so
    /// everything inside a tag goes with it, and it strips `{…}` as JSX
    /// spacing, so object literals go too. Both of those carry real published
    /// copy here:
    ///
    ///   - `__root.tsx`, `index.tsx`, `apply.tsx` and `support.tsx` set
    ///     `name: "description"` and `og:description` as object literals. Those
    ///     are the sentences that appear in a search result and in the card
    ///     when somebody pastes an Anchor link into Slack.
    ///   - `PilotForm.tsx` passes prose to a `description=` attribute, which
    ///     renders under a form field on `/apply`.
    ///
    /// A guard that reads only the text nodes would have covered the legal
    /// pages and missed the sentence a reviewer sees before they ever open one.
    static func publishedSentences(in source: String) -> [String] {
        let text = commentFree(source)
        // String literals are scanned as themselves rather than reconstructed,
        // because a trigger phrase in a `className` cannot occur and a trigger
        // phrase in a meta description certainly can.
        let literals = matches(of: "\"([^\"\\n]{12,})\"", in: text)
            + matches(of: "`([^`]{12,})`", in: text)
        return sentences(in: prose(from: text)) + literals.flatMap { sentences(in: $0) }
    }

    /// The capture group of every match, in order.
    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { r in String(text[r]) }
        }
    }

    /// Comments go first and for a real reason — `pilot-application.ts` opens
    /// with a comment reading *"There is no database"*, which is a true remark
    /// about the pilot form's storage and would otherwise be reported as a
    /// published claim. A developer note is not a published sentence.
    private static func commentFree(_ source: String) -> String {
        var text = source
        // `(?s)` and `(?m)` are load-bearing and were both missing first time
        // round. Without dot-matches-newline the block-comment pattern cannot
        // span the lines a block comment is made of, so it silently matched
        // nothing and `pilot-application.ts`'s header — "There is no database",
        // a true remark about the pilot form — was reported as a published
        // claim. A stripper that strips nothing looks exactly like a file with
        // no comments in it.
        text = text.replacingOccurrences(
            of: "(?s)/\\*.*?\\*/", with: " ", options: [.regularExpression]
        )
        text = text.replacingOccurrences(
            of: "(?m)^\\s*//.*$", with: " ", options: [.regularExpression]
        )
        return text
    }

    /// Comment-free source reduced to its JSX text nodes.
    ///
    /// Crude on purpose: this matches prose, not JSX. What it discards —
    /// everything inside a tag, and everything inside braces — is picked back
    /// up as string literals by `publishedSentences(in:)`, which is the half a
    /// canary had to find.
    private static func prose(from commentFreeSource: String) -> String {
        var text = commentFreeSource
        // `{" "}` and friends are JSX spacing, not words.
        text = text.replacingOccurrences(
            of: "\\{[^{}]*\\}", with: " ", options: [.regularExpression]
        )
        text = text.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: [.regularExpression]
        )
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Split on sentence enders, so a scope word in the *next* sentence cannot
    /// launder an unscoped claim in this one.
    ///
    /// That mattered in the real defect: *"We hold nothing, so there is nothing
    /// for us to delete."* is immediately followed by a list of classroom
    /// items, and a paragraph-level check would have passed it.
    private static func sentences(in prose: String) -> [String] {
        prose.components(separatedBy: CharacterSet(charactersIn: ".:!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func section(withID id: String, in source: String) -> String? {
        guard let start = source.range(of: "id=\"\(id)\"") else { return nil }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "</LegalSectionBody>") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }
}

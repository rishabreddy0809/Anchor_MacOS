//
//  TeacherFacingSourceScanTests.swift
//  AnchorTests
//
//  The vocabulary scan, widened past the two places it happened to start.
//
//  ── Why a third scan rather than more cases in the other two ────────────────
//
//  Anchor already had two guards on what a teacher may be told, and both work.
//  `TeacherFacingCopyTests` scans string literals under `Anchor/Views`.
//  `SupportContactTests` enumerates `ZoomError` and `ClassroomError`. Between
//  them they have caught real strings and they are not being replaced.
//
//  What neither could see is prose that lives in a Model or a Service and still
//  reaches the screen. Four were found on 2026-08-20 by sweeping for it by hand:
//
//    1. `ZoomEmailVerification.detail` said "Add <scope> to the bot's
//       Server-to-Server OAuth app in the Zoom Marketplace, then re-activate the
//       app" — the sentence `SupportContactTests`' own header quotes as the
//       example it exists to prevent, in an enum that scan does not enumerate.
//    2. `ZoomError.invalidCredentials.recoverySuggestion` said "Check the
//       credentials in Settings, or regenerate the Client Secret in the Zoom
//       Marketplace". Settings → Advanced is `#if DEBUG`, so the first half
//       pointed at UI absent from the teacher's build and the second at an
//       account they do not have.
//    3. `ClassroomViewModel` told teachers to add a scope "in the Google Cloud
//       console under APIs & Services → OAuth consent screen → Data access".
//       Wrong reader *and* wrong cause: Google presents the four Classroom
//       permissions as separate tick boxes and one left unticked is the common
//       way to get there, so nothing in any console is missing.
//    4. `ZoomMeetingSDKBridge.describe` is written for the log and was handed
//       straight to `ZoomError.unsupported`, which renders its payload verbatim.
//       "check the Meeting SDK app's Client ID/Secret" went on screen.
//
//  Every one is the same shape: **one sentence written for two readers.** The
//  fix in each case was to split them, not to soften the diagnostic — the log
//  and the support mail still say the developer things.
//
//  ── What this scan skips, and why it is not an exemption list ───────────────
//
//  Two audiences are declared in the code itself rather than by file:
//
//  * `technicalDetail` — the property that exists *to* say these things.
//    `SupportContact.reportURL` folds it into the mail a teacher sends, which is
//    the one place it reaches its reader.
//  * `AnchorDiag.operatorMessage` — stderr, read by the admin in the Terminal
//    they ran the provisioning command from.
//  * `diagnosticDescription` — the log-and-support-mail half of a pair whose
//    other half is teacher-facing. `ZoomMeetingSDKBridge` has exactly one, and
//    it is named that *because* its previous name, `describe`, said nothing
//    about who reads it and it was rendered to a teacher for months.
//
//  Both are skipped by what the string *is*, not by which file holds it. There
//  is no per-file exemption, deliberately: `TeacherFacingCopyTests` records that
//  its first version carried one and that the exemption was the hole.
//
//  ── Why "keychain" is not on this list ─────────────────────────────────────
//
//  It is on `SupportContactTests`' list and stays there. The term appears in two
//  roles: "not in the Keychain" in a diagnostic, and "Anchor couldn't save the
//  Zoom sign-in to your Keychain" on screen — where it names a thing on the
//  teacher's own Mac, visible in an app Apple ships them, and hands them no
//  impossible instruction. The list here holds only terms that unambiguously
//  denote a console or account the reader does not have. Widening the reach of
//  a scan and widening its vocabulary are separate decisions, and doing both at
//  once is how a good guard gets disabled for noise.
//

import XCTest
@testable import Anchor

final class TeacherFacingSourceScanTests: XCTestCase {

    /// Terms that name a console, marketplace or credential the teacher does
    /// not have. Every one of these was found in live copy at some point.
    private let developerVocabulary = [
        "client id", "client secret", "account id", "sdk key", "api key",
        "marketplace", "cloud console", "google cloud", "apis & services",
        "oauth consent", "server-to-server", "re-activate", "scope to your",
        "under advanced", "→ advanced"
    ]

    // MARK: - The rule

    func testNoProseOutsideAViewTellsATeacherToDoSomethingOnlyADeveloperCan() throws {
        var offences: [String] = []

        for (name, source) in try swiftSources() {
            for (line, text, term) in offendingLiterals(in: source) {
                offences.append("\(name):\(line) [\(term)] \"\(text)\"")
            }
        }

        XCTAssertTrue(
            offences.isEmpty,
            """
            These reach a teacher and name something only a developer or admin can do. \
            Split the sentence: say plainly that it is Anchor's end and whose it is to \
            fix, and move the diagnostic to `technicalDetail` or \
            `AnchorDiag.operatorMessage`, both of which this scan skips by design.

            \(offences.joined(separator: "\n"))
            """
        )
    }

    // MARK: - The split itself, pinned rather than inferred

    // The scan proves no *literal* carries developer vocabulary. It cannot
    // prove the right half of a split pair is the one that reaches the teacher,
    // because that is a call site rather than a string — and the call site is
    // exactly what went wrong: `describe` was correct, and handing it to
    // `ZoomError.unsupported` is what put it on screen.
    //
    // Asserted against the source rather than by calling the function, because
    // `ZoomSDKAuthError` comes from the vendored SDK and the test target does
    // not link it. That is a real limit and worth naming: nothing here executes
    // the bridge, so these check the shape of the code, not its behaviour.

    func testTheDiagnosticHalfIsOnlyEverLogged() throws {
        let bridge = try XCTUnwrap(
            try swiftSources().first { $0.name == "ZoomMeetingSDKBridge.swift" }
        )
        var offences: [String] = []
        for (index, raw) in bridge.source.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.contains("diagnosticDescription("), !line.hasPrefix("//"),
                  !line.contains("static func") else { continue }
            guard line.contains("AnchorDiag.") else {
                offences.append("line \(index + 1): \(line)")
                continue
            }
        }
        XCTAssertTrue(
            offences.isEmpty,
            """
            `diagnosticDescription` is read somewhere other than a log call. It names the             Meeting SDK app, its Client ID/Secret and the Marketplace; anything that renders             it puts those in front of a teacher. Use `teacherFacingAuthFailure` there.

            \(offences.joined(separator: "\n"))
            """
        )
    }

    func testTheTeacherFacingHalfReassuresRatherThanJustFailing() throws {
        // A bot that cannot authenticate leaves the dashboard correctly empty of
        // live signal while everything else keeps working. If the message does
        // not say so, a teacher reads a working app as a dead one — which is the
        // difference between a pilot that continues and one that quietly stops.
        let bridge = try XCTUnwrap(
            try swiftSources().first { $0.name == "ZoomMeetingSDKBridge.swift" }
        )
        let body = try XCTUnwrap(
            bridge.source.components(separatedBy: "static func teacherFacingAuthFailure").last,
            "teacherFacingAuthFailure is gone; the split has been undone."
        ).prefix(1200)
        XCTAssertTrue(
            String(body).contains("still works"),
            "The teacher-facing SDK auth failure no longer says the rest of Anchor is "
            + "unaffected."
        )
    }

    // MARK: - Vacuity guards

    func testTheScanFoundTheSource() throws {
        let sources = try swiftSources()
        XCTAssertGreaterThan(sources.count, 40, "found \(sources.count) files — the path is wrong")
        for required in ["ZoomModels.swift", "ClassroomViewModel.swift", "ZoomMeetingSDKBridge.swift"] {
            XCTAssertTrue(
                sources.contains { $0.name == required },
                "\(required) is not being scanned, and it held one of the strings this was "
                + "written for."
            )
        }
    }

    func testTheScanStillSeesProseItShouldNotFlag() throws {
        // The counterpart guard, and the one that would catch the scan being
        // quietly neutered — by a bad `#if` tracker, a broken literal regex, or
        // a skip rule that swallowed everything. If the scanner cannot find any
        // ordinary sentence, its silence above means nothing.
        let sources = try swiftSources()
        let prose = sources.flatMap { literals(in: $0.source) }
            .filter { $0.text.contains(" ") && $0.text.count > 30 }
        XCTAssertGreaterThan(
            prose.count, 100,
            "The scanner found almost no prose at all, so it is not reading strings."
        )
    }

    func testTheSkipRulesAreNarrowerThanTheFilesTheyAppearIn() throws {
        // `ZoomModels.swift` holds both the exempt `technicalDetail` and plenty
        // of teacher-facing copy. If the skip were file-shaped rather than
        // property-shaped, the whole file would vanish from the scan and the
        // strings this suite exists for would go unread.
        let zoomModels = try XCTUnwrap(
            try swiftSources().first { $0.name == "ZoomModels.swift" }
        )
        let seen = literals(in: zoomModels.source).map(\.text)
        XCTAssertTrue(
            seen.contains { $0.contains("No Zoom account is connected") },
            "Teacher-facing copy in ZoomModels is being skipped along with its technicalDetail."
        )
        XCTAssertFalse(
            seen.contains { $0.contains("resolved empty") },
            "A technicalDetail string was scanned; the skip rule is not working."
        )
    }

    // MARK: - Scanning

    private func swiftSources() throws -> [(name: String, source: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
            .appendingPathComponent("Anchor")
        let walker = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )
        var files: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            files.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }

    private func offendingLiterals(in source: String) -> [(Int, String, String)] {
        literals(in: source).compactMap { candidate in
            let lowered = candidate.text.lowercased()
            guard let term = developerVocabulary.first(where: { lowered.contains($0) }) else {
                return nil
            }
            return (candidate.line, candidate.text, term)
        }
    }

    /// Prose string literals the shipped app can show, with the two declared
    /// non-teacher audiences removed.
    ///
    /// A literal must contain a space to count. `"server-to-server-oauth"` in
    /// `Constants` is an identifier, not a sentence, and matching it would put
    /// permanent noise in front of a real finding — which is how a scan gets
    /// switched off.
    private func literals(in source: String) -> [(line: Int, text: String)] {
        var found: [(Int, String)] = []
        var branches: [Bool] = []
        var technicalDetailDepth: Int?
        var depth = 0
        var operatorMessageDepth: Int?

        for (index, raw) in source.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Same `#if` tracking as TeacherFacingCopyTests and ReleaseHygiene:
            // a string the shipped binary does not contain cannot be read.
            if line.hasPrefix("#if") { branches.append(line.contains("DEBUG")); continue }
            if line.hasPrefix("#endif") { if !branches.isEmpty { branches.removeLast() }; continue }
            if line.hasPrefix("#else"), !branches.isEmpty {
                branches[branches.count - 1].toggle(); continue
            }

            let opens = line.filter { $0 == "{" }.count + line.filter { $0 == "(" }.count
            let closes = line.filter { $0 == "}" }.count + line.filter { $0 == ")" }.count

            if line.contains("var technicalDetail")
                || line.contains("func diagnosticDescription") { technicalDetailDepth = depth }
            if line.contains("AnchorDiag.operatorMessage") { operatorMessageDepth = depth }

            let insideSkippedAudience = technicalDetailDepth != nil || operatorMessageDepth != nil
            let visible = !branches.contains(true)
                && !insideSkippedAudience
                && !line.hasPrefix("//")

            if visible {
                for text in matches(in: line) where text.contains(" ") && text.count >= 12 {
                    found.append((index + 1, text))
                }
            }

            depth += opens - closes
            if let start = technicalDetailDepth, depth <= start { technicalDetailDepth = nil }
            if let start = operatorMessageDepth, depth <= start { operatorMessageDepth = nil }
        }
        return found
    }

    private func matches(in line: String) -> [String] {
        // Interpolations are stripped rather than skipped: a literal is still
        // prose when it carries a `\(count)`, and dropping the whole line would
        // silently exempt most real copy.
        var results: [String] = []
        var current = ""
        var inString = false
        var previous: Character = " "
        for character in line {
            if character == "\"", previous != "\\" {
                if inString { results.append(current); current = "" }
                inString.toggle()
            } else if inString {
                current.append(character)
            }
            previous = character
        }
        return results
    }
}

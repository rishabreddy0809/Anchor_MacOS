//
//  TeacherFacingCopyTests.swift
//  AnchorTests
//
//  The same rule `SupportContactTests` enforces on the error enums, applied to
//  the string literals written directly in views.
//
//  Why a second file rather than more cases in the first. `SupportContactTests`
//  can enumerate `ZoomError` and `ClassroomError` and ask each one what it says,
//  because those are values. A `Text("…")` inside a SwiftUI body is not
//  reachable that way — there is no value to interrogate — so the only thing
//  that can check it is the source.
//
//  This exists because the enum tests gave false confidence. They passed while
//  five separate view literals told teachers to do impossible things, and all
//  five were found by hand, one at a time, while doing something else:
//
//    - three in SettingsView ("Add one under Advanced" twice, plus course
//      selection described as living under Advanced when it never did),
//    - one in ConnectionStatusView pointing at the same vanished disclosure,
//    - and one in HomeView that was simply false — "Anchor ships no Google
//      credentials of its own", written before the client ID shipped on
//      2026-08-17 and never revisited.
//
//  Finding those by accident is not a strategy. Hence a scan.
//

import XCTest
@testable import Anchor

final class TeacherFacingCopyTests: XCTestCase {

    /// Words that mean the reader is expected to hold a developer or admin
    /// account somewhere, or to know how Anchor is built.
    private let developerVocabulary = [
        "client id", "client secret", "account id", "sdk key", "api key",
        "marketplace", "cloud console", "google cloud", "apis & services",
        "oauth consent", "server-to-server", "oauth app", "redirect url",
        "under advanced", "re-activate"
    ]

    /// Files whose credential UI is Debug-only but gated at the *call site*
    /// rather than the declaration, so the strings are still in the source a
    /// scan can see.
    ///
    /// This is recorded debt, not an exemption on principle. Both files hold a
    /// `advancedDisclosure` that a Release build never renders — but
    /// `ConnectionStatusView` shares `testResult` between that Debug-only form
    /// and the status row every teacher sees, so hoisting the declarations
    /// behind `#if DEBUG` is a real refactor rather than a wrapper. Until that
    /// happens these two are scanned only for the vocabulary that would be
    /// wrong *anywhere*, below.
    private let callSiteGatedFiles = [
        "ConnectionStatusView.swift",
        "ClassroomConnectionPanel.swift"
    ]

    /// Phrases that are wrong in any file, gated or not, because they send the
    /// reader somewhere that does not exist in the build they are holding.
    private let alwaysWrong = ["under advanced"]

    // MARK: - The rule

    func testNoViewTellsATeacherToDoSomethingOnlyADeveloperCan() throws {
        var offences: [String] = []

        for url in try viewSources() {
            let isGated = callSiteGatedFiles.contains(url.lastPathComponent)
            let terms = isGated ? alwaysWrong : developerVocabulary
            let source = try String(contentsOf: url, encoding: .utf8)

            for (line, text, term) in literals(in: source, matching: terms) {
                offences.append("\(url.lastPathComponent):\(line) [\(term)] \"\(text)\"")
            }
        }

        XCTAssertTrue(
            offences.isEmpty,
            """
            These are shown to a teacher and describe something they cannot do. \
            Say plainly that it is Anchor's end and offer SupportContact instead:

            \(offences.joined(separator: "\n"))
            """
        )
    }

    /// A scan that cannot see the files proves nothing, and would keep passing
    /// forever after a directory rename.
    func testTheScanFoundTheViews() throws {
        let views = try viewSources()
        XCTAssertGreaterThan(views.count, 20, "found \(views.count) view files — the path is wrong")
        XCTAssertTrue(
            views.contains { $0.lastPathComponent == "HomeView.swift" },
            "HomeView is not being scanned, and it held one of the strings this was written for"
        )
    }

    // MARK: - Scanning

    private func viewSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // AnchorTests/
            .deletingLastPathComponent()        // repo root
            .appendingPathComponent("Anchor/Views")

        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }

        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// String literals of prose length containing one of `terms`.
    ///
    /// The 12-character floor is what keeps this usable: shorter literals are
    /// overwhelmingly SF Symbol names, dictionary keys and format fragments,
    /// and matching those would bury a real finding in noise until someone
    /// disabled the test. Comment lines are skipped for the same reason — a
    /// comment explaining why a string was changed is not the string.
    private func literals(
        in source: String,
        matching terms: [String]
    ) -> [(Int, String, String)] {
        var found: [(Int, String, String)] = []

        for (index, raw) in source.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("//"), !line.hasPrefix("///"), !line.hasPrefix("*") else { continue }

            let pattern = try? NSRegularExpression(pattern: "\"([^\"\\\\]{12,})\"")
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            pattern?.enumerateMatches(in: line, range: range) { match, _, _ in
                guard let match, let r = Range(match.range(at: 1), in: line) else { return }
                let text = String(line[r])
                let lowered = text.lowercased()
                for term in terms where lowered.contains(term) {
                    found.append((index + 1, text, term))
                    break
                }
            }
        }

        return found
    }
}

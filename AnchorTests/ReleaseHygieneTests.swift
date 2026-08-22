//
//  ReleaseHygieneTests.swift
//  AnchorTests
//
//  What must not be in a build handed to a teacher.
//
//  This is a source-scanning test rather than a behavioural one, which is
//  unusual enough to justify. The defect it guards has no runtime symptom in
//  the only build anyone runs while developing: a `print` in a Debug build goes
//  to the Xcode console, where it looks correct and useful. The same line in a
//  Release build goes to the unified log, where anyone with Console.app and the
//  Mac can read it — and `ZoomMeetingSDKBridge` was printing a student's name on
//  every chat message. Nothing failed. Nothing looked wrong. It would have
//  shipped.
//
//  `AnchorDiag` already stated the correct policy in its own header — "Debug
//  builds only ... because these lines carry student names and email addresses;
//  they must never be able to reach a shipped build" — and the bridge simply
//  never used it, printing the same `ANCHOR-DIAG` prefix by hand instead. A
//  policy a file can opt out of by not importing it is not a policy, so it is
//  asserted here across the whole target.
//
//  Anchor's entire privacy claim is that class data stays on this Mac. A log
//  line is data leaving the app, so this is that claim's test.
//

import XCTest
@testable import Anchor

final class ReleaseHygieneTests: XCTestCase {

    /// Console calls that reach a Release build. `AnchorDiag` wraps `print` and
    /// `Logger` in `#if DEBUG`, so it is the sanctioned route and is exempt.
    private let unconditionalLoggingCalls = ["print(", "NSLog(", "debugPrint("]

    /// Source files allowed to make those calls directly.
    private let exemptFiles = ["AnchorDiag.swift"]

    /// Terms that mean the value being logged describes a person in the class.
    ///
    /// **Why `Logger` and `os_log` are deliberately absent from the list above,
    /// which looked like a hole on 2026-08-21 and is not one.** Seven files
    /// hold a `Logger`, six of them outside the exemption, including
    /// `ZoomMeetingSDKBridge` — the very file this test was written for. They
    /// write to the same unified log. The difference is redaction: **OSLog
    /// renders dynamic strings and objects as `<private>` by default**, while
    /// `print` writes whatever it is handed, verbatim. A student's name is a
    /// `String`, so `Logger` hides it and `print` does not. That is the whole
    /// reason one is banned and the other is the sanctioned route, and it was
    /// nowhere written down until an audit went looking for the hole.
    ///
    /// **Numbers are the exception: OSLog leaves them public by default.** That
    /// is right for the counts and result codes these files log, which say
    /// nothing about a person.
    ///
    /// So the only way a name reaches a Release log through `Logger` is if
    /// someone asks for it with `privacy: .public`. That is the escape hatch,
    /// and `testNoStudentIdentityIsPublishedToTheLog` is what watches it.
    private let studentIdentifyingTerms = [
        "student", "email", "userName", "displayName",
        "participant", "rosterKey", "matchKey", "attendee"
    ]

    // MARK: - The rule

    func testNoSourceFileLogsToTheConsoleOutsideDebug() throws {
        var offences: [String] = []

        for url in try swiftSources() where !exemptFiles.contains(url.lastPathComponent) {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (line, text) in offendingLines(in: source) {
                offences.append("\(url.lastPathComponent):\(line): \(text)")
            }
        }

        XCTAssertTrue(
            offences.isEmpty,
            """
            These reach a Release build's unified log, where they are readable \
            with Console.app. Route them through AnchorDiag.log, which is \
            #if DEBUG:

            \(offences.joined(separator: "\n"))
            """
        )
    }

    /// Nothing describing a person in the class may be forced past OSLog's
    /// default redaction.
    ///
    /// Deliberately narrow. It does **not** flag every `privacy: .public`,
    /// because there are thirty of them and all but two are result codes,
    /// counts, HTTP paths, error descriptions and Anchor's own filenames —
    /// exactly what a diagnostic is for. A guard that made someone justify
    /// `\(http.statusCode, privacy: .public)` would teach them the list is
    /// noise, and that is how the real one gets waved through. The same
    /// mistake was made and corrected on 2026-08-21 in
    /// `PrivacyDisclosureTests`, whose first scan matched every
    /// `com.anchor.*` literal and dragged in the diagnostics subsystem.
    ///
    /// **The two that are neither a code nor a count are `course.name`**
    /// (`ClassroomViewModel`, twice). A course name is school data rather than
    /// a child's, so it does not trip this rule — but it is a real name in a
    /// Release log and it is recorded in `ship-checklist.md` as Rishab's call
    /// rather than silently allowed here.
    func testNoStudentIdentityIsPublishedToTheLog() throws {
        var offences: [String] = []

        for url in try swiftSources() where !exemptFiles.contains(url.lastPathComponent) {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (line, text) in source.components(separatedBy: .newlines).enumerated() {
                for expression in publishedExpressions(in: text) {
                    // An aggregate over people is not a person. `students.count`
                    // is the number in the room and says nothing about any of
                    // them, so it must not be flagged.
                    //
                    // The first version of this scanned the whole line instead
                    // of the interpolated expression and failed on exactly that
                    // — matching "student" inside "students.count" — which is
                    // the over-broad-guard mistake this file's own comment
                    // warns about two paragraphs up. Written down because
                    // making it while warning against it is the point.
                    let aggregates = [".count", ".isEmpty", ".indices", ".first", ".last"]
                    guard !aggregates.contains(where: { expression.hasSuffix($0) }) else { continue }

                    let lowered = expression.lowercased()
                    guard studentIdentifyingTerms.contains(where: { lowered.contains($0.lowercased()) })
                    else { continue }

                    offences.append(
                        "\(url.lastPathComponent):\(line + 1): \(expression)"
                    )
                }
            }
        }

        XCTAssertTrue(
            offences.isEmpty,
            """
            These force a value describing someone in the class past OSLog's \
            default redaction, so it lands verbatim in the unified log where \
            Console.app can read it. Drop the `privacy: .public` and let OSLog \
            redact it, or log a count instead of the person:

            \(offences.joined(separator: "\n"))
            """
        )
    }

    /// The scan is only worth anything if it can actually see the source. A
    /// wrong path would make the test above pass silently forever.
    func testTheScanFoundTheSourceTree() throws {
        let sources = try swiftSources()
        XCTAssertGreaterThan(sources.count, 50, "found \(sources.count) files — the path is wrong")
        XCTAssertTrue(
            sources.contains { $0.lastPathComponent == "ZoomMeetingSDKBridge.swift" },
            "the file this test was written for is not being scanned"
        )
    }

    // MARK: - Scanning

    /// The expressions a line forces past OSLog's redaction.
    ///
    /// Returns what is inside `\(` … `, privacy: .public)`, so the rule reads
    /// the value being published rather than the sentence around it. A line
    /// like `"Synced \(course.name, privacy: .public): \(n, privacy: .public)"`
    /// yields two expressions and each is judged on its own.
    private func publishedExpressions(in line: String) -> [String] {
        guard line.contains("privacy: .public") else { return [] }
        var found: [String] = []
        var rest = Substring(line)

        while let marker = rest.range(of: ", privacy: .public") {
            let before = rest[rest.startIndex..<marker.lowerBound]
            // Walk back to the `\(` that opened this interpolation, counting
            // nested parens so a call like `f(a, b)` inside it stays intact.
            var depth = 0
            var start: String.Index?
            var i = before.endIndex
            while i > before.startIndex {
                i = before.index(before: i)
                let c = before[i]
                if c == ")" { depth += 1 }
                else if c == "(" {
                    if depth == 0 {
                        if i > before.startIndex, before[before.index(before: i)] == "\\" { start = before.index(after: i) }
                        break
                    }
                    depth -= 1
                }
            }
            if let start { found.append(String(before[start...]).trimmingCharacters(in: .whitespaces)) }
            rest = rest[marker.upperBound...]
        }
        return found
    }

    /// Every Swift file in the app target, located relative to this test file
    /// so the scan follows the repository rather than a build directory.
    private func swiftSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)      // AnchorTests/ReleaseHygieneTests.swift
            .deletingLastPathComponent()                // AnchorTests/
            .deletingLastPathComponent()                // repo root
            .appendingPathComponent("Anchor")

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Lines making a logging call while no enclosing `#if DEBUG` is open.
    ///
    /// Tracks `#if` nesting rather than pattern-matching a single line, because
    /// the call and its guard are usually several lines apart. `#else` flips the
    /// innermost branch: the else-arm of `#if DEBUG` is exactly the Release
    /// build, so a call there is an offence even though "DEBUG" is on screen
    /// directly above it.
    private func offendingLines(in source: String) -> [(Int, String)] {
        var branches: [Bool] = []
        var found: [(Int, String)] = []

        for (index, raw) in source.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("#if") {
                branches.append(line.contains("DEBUG"))
                continue
            }
            if line.hasPrefix("#endif") {
                if !branches.isEmpty { branches.removeLast() }
                continue
            }
            if line.hasPrefix("#else"), !branches.isEmpty {
                branches[branches.count - 1].toggle()
                continue
            }

            // Comments describing a call are not a call.
            guard !line.hasPrefix("//"), !line.hasPrefix("///"), !line.hasPrefix("*") else { continue }
            guard !branches.contains(true) else { continue }

            for call in unconditionalLoggingCalls where line.contains(call) {
                // `.print(` and `somethingPrint(` are other methods entirely.
                let precedesIdentifier = line.range(of: "[A-Za-z0-9_.]\\Q\(call)\\E", options: .regularExpression)
                guard precedesIdentifier == nil else { continue }
                found.append((index + 1, line))
                break
            }
        }

        return found
    }
}

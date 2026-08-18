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

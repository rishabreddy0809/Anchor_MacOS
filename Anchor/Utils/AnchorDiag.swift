//
//  AnchorDiag.swift
//  Anchor
//
//  Console tracing for the parts of the app whose failures are invisible from
//  the UI — chiefly identity: which address Zoom reported for whom, and why a
//  participant did or didn't land on a Classroom roster entry.
//
//  Debug builds only. `#if DEBUG` rather than a settings toggle because these
//  lines carry student names and email addresses; they must never be able to
//  reach a shipped build.
//

import Foundation
import os

nonisolated enum AnchorDiag {

    /// Prefix chosen to match the SDK bridge's existing tracing, so one filter
    /// in the Xcode console catches everything.
    private static let prefix = "ANCHOR-DIAG"

    /// Also goes to the unified log, so a build launched from Finder — where
    /// stdout goes nowhere — can still be read with:
    ///
    ///     log stream --style compact --predicate 'subsystem == "com.anchor.diag"'
    private static let logger = Logger(subsystem: "com.anchor.diag", category: "identity")

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        print("\(prefix) \(text)")
        logger.debug("\(text, privacy: .public)")
        #endif
    }

    /// A message for the person who launched Anchor from a Terminal to
    /// provision it — and the one thing here that is **not** `#if DEBUG`.
    ///
    /// Three reasons it is exempt rather than an oversight:
    ///
    ///   * **It has a reader in a Release build, and `log` above does not.**
    ///     Provisioning in a shipped build *is* a Terminal launch
    ///     (ADMIN-SETUP.md step 3), so the admin is standing at a shell with
    ///     stderr attached. A refusal they cannot see is the silent no-op this
    ///     exists to replace.
    ///   * **It is not the harm `ReleaseHygieneTests` guards.** That rule bans
    ///     `print`/`NSLog`/`debugPrint` because they reach the *unified log*,
    ///     which anyone with Console.app can read, and the defect behind it was
    ///     a student's name being written there every chat message. stderr goes
    ///     to the launching process's stream and nowhere else.
    ///   * **It can only ever carry variable names.** Never a credential value,
    ///     never anything about a class or a student — call sites pass fixed
    ///     strings. Keep it that way: this is the one channel here that
    ///     survives into a build a teacher runs.
    static func operatorMessage(_ message: String) {
        FileHandle.standardError.write(Data(("Anchor: " + message + "\n").utf8))
    }

    /// Logs only when the message changes, for callers on a polling loop.
    ///
    /// The identity trace runs on every 10-second refresh and is identical
    /// between refreshes until someone joins, leaves or renames themselves —
    /// unfiltered it would bury the one line that changed.
    static func logIfChanged(key: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        lock.lock()
        let isNew = lastMessages[key] != text
        if isNew { lastMessages[key] = text }
        lock.unlock()
        guard isNew else { return }
        print("\(prefix) \(text)")
        logger.debug("\(text, privacy: .public)")
        #endif
    }

    #if DEBUG
    nonisolated(unsafe) private static var lastMessages: [String: String] = [:]
    private static let lock = NSLock()
    #endif
}

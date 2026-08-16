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

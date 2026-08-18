//
//  ZoomMeetingLink.swift
//  Anchor
//
//  Turns whatever a teacher pasted into a meeting number and a passcode.
//
//  What they actually paste is almost never a meeting number. It is the whole
//  invitation, forwarded out of Outlook or Google Calendar — a paragraph of
//  prose, a join URL, a grouped "Meeting ID: 812 3456 7890", a passcode on its
//  own line, and a block of international dial-in numbers underneath. Asking
//  them to pick the digits out of that and type them into one box, and the
//  passcode into another, is asking them to do a parser's job by hand while a
//  class waits.
//
//  ## Why this never scans for "the first long number"
//
//  Because the dial-in block would win. A Zoom invitation contains lines like
//  "+1 312 626 6799 US (Chicago)", which is eleven digits once the punctuation
//  is stripped — exactly as many as a personal meeting id, and appearing before
//  the meeting id in some layouts. A parser that hunts for a plausible digit run
//  finds a phone number and joins nothing, with an error that blames the
//  teacher's paste.
//
//  So digits are only ever read from somewhere that names them: the path of a
//  join URL, a `confno` parameter, an explicit "Meeting ID:" label, or an input
//  that is nothing but the number. Free text is never searched. That is the
//  whole design, and it is why the tests lean on the invitation blob.
//
//  ## Which passcode
//
//  An invitation usually carries two, and they are not interchangeable. The
//  `pwd=` in the join URL is an encoded form meant for the browser; the digits
//  after "Passcode:" are what a human types into a client, which is what
//  `ZoomSDKJoinMeetingElements.password` expects. Where both are present the
//  labelled one wins. The URL parameter is still read as a fallback, because a
//  bare link with no invitation text around it is the other common paste and a
//  passcode that might work beats none at all.
//

import Foundation

nonisolated struct ZoomMeetingLink: Sendable, Equatable {

    /// Bare digits, ready for `BotJoinRequest`.
    var meetingNumber: String
    /// The passcode a human would type, when the paste carried one.
    var passcode: String?

    /// Zoom meeting and webinar ids are 9, 10 or 11 digits; personal meeting
    /// ids sit at the top of that range. Length is the only cheap check
    /// available — there is no checksum — so it is used to reject a match
    /// rather than to find one.
    static let validNumberLengths = 9...11

    /// - Returns: nil when nothing in `raw` names a meeting number. A vanity
    ///   personal-room link (`zoom.us/my/alice`) lands here on purpose: it
    ///   carries no id, and guessing would be worse than saying so.
    static func parse(_ raw: String) -> ZoomMeetingLink? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let number = meetingNumber(in: text) else { return nil }

        return ZoomMeetingLink(meetingNumber: number, passcode: passcode(in: text))
    }

    // MARK: - Meeting number

    private static func meetingNumber(in text: String) -> String? {
        // The whole paste is the number, however it was grouped. Checked first
        // because it is unambiguous and the most common thing typed by hand.
        if let bare = bareNumber(in: text) { return bare }

        // A join URL. `/j/` is a meeting, `/w/` a webinar, `/s/` the host's own
        // start link — a teacher who copied from their own Zoom window rather
        // than from the invitation will have that last one.
        for marker in ["/j/", "/w/", "/s/"] {
            if let found = digitsFollowing(marker, in: text) { return found }
        }

        // The zoommtg:// deep link the desktop client registers.
        if let found = digitsFollowing("confno=", in: text) { return found }

        return labelledNumber(in: text)
    }

    /// Digits only, once grouping spaces and dashes are removed — and only when
    /// there is nothing else in the string at all.
    private static func bareNumber(in text: String) -> String? {
        let stripped = text.filter { !$0.isWhitespace && $0 != "-" && $0 != "\u{2013}" }
        guard !stripped.isEmpty, stripped.allSatisfy(\.isNumber),
              validNumberLengths.contains(stripped.count)
        else { return nil }
        return stripped
    }

    /// The digit run immediately after `marker`.
    ///
    /// Keeps searching when a hit is the wrong length rather than giving up, so
    /// one malformed occurrence earlier in a long invitation cannot mask the
    /// real one further down.
    private static func digitsFollowing(_ marker: String, in text: String) -> String? {
        var searchFrom = text.startIndex
        while let found = text.range(
            of: marker,
            options: .caseInsensitive,
            range: searchFrom..<text.endIndex
        ) {
            let run = text[found.upperBound...].prefix { $0.isNumber }
            if validNumberLengths.contains(run.count) { return String(run) }
            searchFrom = found.upperBound
        }
        return nil
    }

    /// The number on a line that announces itself as one.
    private static func labelledNumber(in text: String) -> String? {
        for label in ["meeting id:", "meeting number:", "webinar id:"] {
            guard let found = text.range(of: label, options: .caseInsensitive) else { continue }

            // Digits, allowing the spaces and dashes Zoom groups them with, and
            // stopping at anything else — so a label and a passcode sharing one
            // line don't run together into a 17-digit number that matches
            // nothing.
            var digits = ""
            for character in text[found.upperBound...] {
                if character.isNumber {
                    digits.append(character)
                    if digits.count == validNumberLengths.upperBound { break }
                } else if character == " " || character == "-" || character == "\u{00A0}" {
                    continue
                } else {
                    break
                }
            }
            if validNumberLengths.contains(digits.count) { return digits }
        }
        return nil
    }

    // MARK: - Passcode

    private static func passcode(in text: String) -> String? {
        // The labelled one first — see the file header for why the two are not
        // interchangeable.
        for label in ["passcode:", "password:"] {
            guard let found = text.range(of: label, options: .caseInsensitive) else { continue }
            let token = text[found.upperBound...]
                .drop { $0 == " " || $0 == "\u{00A0}" }
                .prefix { !$0.isWhitespace }
            if !token.isEmpty { return String(token) }
        }

        return queryValue("pwd", in: text)
    }

    /// A query parameter's value, read case-sensitively out of the original
    /// string — a passcode is case-sensitive even though the parameter name
    /// isn't.
    private static func queryValue(_ name: String, in text: String) -> String? {
        var searchFrom = text.startIndex
        while let found = text.range(
            of: "\(name)=",
            options: .caseInsensitive,
            range: searchFrom..<text.endIndex
        ) {
            // Anchored to a parameter boundary so `pwd=` cannot be matched
            // inside a longer name that happens to end the same way.
            let isBoundary = found.lowerBound == text.startIndex
                || text[text.index(before: found.lowerBound)] == "?"
                || text[text.index(before: found.lowerBound)] == "&"

            if isBoundary {
                let value = text[found.upperBound...].prefix {
                    $0 != "&" && $0 != "#" && !$0.isWhitespace
                }
                if !value.isEmpty { return String(value) }
            }
            searchFrom = found.upperBound
        }
        return nil
    }
}

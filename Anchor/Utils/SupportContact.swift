//
//  SupportContact.swift
//  Anchor
//
//  The one place Anchor's support address lives, and the pre-filled mail it
//  opens when something breaks in front of a teacher.
//
//  Why this exists. Anchor's error strings were written by the person who also
//  wrote the Zoom and Google integrations, so the ones about *setup* read as
//  instructions to that person: "add the scope to your Server-to-Server OAuth
//  app, then re-activate it", "create a Meeting SDK app in the Zoom
//  Marketplace". A teacher can do none of that. Telling them to is worse than
//  saying nothing, because an instruction implies the reader is the one who
//  erred — so a teacher reads a misconfigured build as their own mistake and
//  stops, rather than reporting it. Those errors now say plainly that it is
//  Anchor's end and hand over this instead.
//
//  The technical sentence is not deleted, only moved: `technicalDetail` on each
//  error carries it into the diagnostics block below, so it arrives in the
//  support mail where it is useful to the one person who can act on it.
//
//  The address is duplicated from the marketing site's `CONTACT_EMAIL`
//  (`website/landing/src/lib/site.ts`) rather than shared — the app has no
//  build-time link to that package. `SupportContactTests` pins the pair, so a
//  change on one side is caught by the suite rather than by a teacher whose
//  mail bounces.
//

import Foundation

nonisolated enum SupportContact {

    /// Must equal `CONTACT_EMAIL` in `website/landing/src/lib/site.ts`.
    static let email = "rishabreddy0809@gmail.com"

    /// The public support page, for the cases where a link is friendlier than
    /// opening a mail composer — chiefly Settings, where nothing has gone
    /// wrong yet and the teacher is browsing rather than blocked.
    static let supportPageURL = URL(string: "https://anchorteach.vercel.app/support")!

    // MARK: - Composing a report

    /// A `mailto:` that opens the teacher's mail client with the subject, the
    /// error, and the build already filled in.
    ///
    /// Everything after the first line is diagnostics rather than prose,
    /// because the teacher is being asked to press Send on a message they did
    /// not write and should be able to read in one glance to satisfy
    /// themselves it carries nothing about their students. It carries no
    /// student data by construction: the only interpolated value is
    /// `detail`, which callers pass from an error's own description.
    ///
    /// - Parameter detail: the technical sentence for whoever reads the mail —
    ///   normally `AnchorError.technicalDetail`. Nil where there isn't one.
    static func reportURL(summary: String, detail: String? = nil) -> URL? {
        var body = """
        \(bodyPreamble)

        ── What Anchor reported ──
        \(summary)
        """

        if let detail, !detail.isEmpty {
            body += "\n\(detail)"
        }

        body += "\n\n── This build ──\n\(diagnostics)"

        // `mailto:` bodies must be percent-encoded, and `.urlQueryAllowed`
        // is not enough on its own: it permits `&` and `+`, which a mail
        // client reads as a parameter separator and a space. Both appear in
        // ordinary error text, so subtracting them is what stops a body from
        // being truncated mid-sentence.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+"))
        guard let encodedSubject = "Anchor: \(summary)".addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }

        return URL(string: "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)")
    }

    /// Sits above the diagnostics so the teacher sees a human sentence first
    /// and knows what they are sending.
    private static let bodyPreamble = """
    (Anything you can add about what you were doing helps — otherwise just send this as is.)
    """

    /// Build and OS, which is most of what a bug report needs and none of
    /// what a teacher should have to go looking for. Deliberately excludes
    /// anything about a class, a roster or a student.
    static var diagnostics: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion

        return """
        Anchor \(version) (\(build))
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        """
    }
}

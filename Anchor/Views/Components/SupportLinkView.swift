//
//  SupportLinkView.swift
//  Anchor
//
//  The two ways a teacher reaches a human: a permanent entry in Settings, and
//  an offer attached to the errors they cannot do anything about.
//
//  Both go through `SupportContact` so the address and the diagnostics block
//  are defined once. See that file for why setup errors stopped carrying
//  instructions.
//

import AppKit
import SwiftUI

/// Opens a pre-filled report. Used where something has already gone wrong, so
/// the summary and technical detail are known at the point of the failure.
struct SupportMailButton: View {
    let summary: String
    var detail: String?
    var label = "Email support"

    var body: some View {
        Button(label) {
            // A failure to build the URL must not look like a dead button:
            // fall back to the plain address, which still opens a composer
            // addressed correctly — only without the diagnostics.
            let url = SupportContact.reportURL(summary: summary, detail: detail)
                ?? URL(string: "mailto:\(SupportContact.email)")
            if let url { NSWorkspace.shared.open(url) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// An error as a teacher should meet it: what happened, then either something
/// they can do or a way to reach someone who can.
///
/// `isSetupProblem` is what picks between those two. It is passed in rather
/// than read off a protocol because `ZoomError` and `ClassroomError` are
/// separate enums that answer the same question — see `ZoomError.isSetupProblem`.
struct ErrorNotice: View {
    let message: String
    var isSetupProblem = false
    var technicalDetail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 10.5))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.riskHigh)

            if isSetupProblem {
                SupportMailButton(summary: message, detail: technicalDetail)
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }
}

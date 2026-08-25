//
//  SignInSheet.swift
//  Anchor
//
//  The account screen on its own, presented from Settings → Account.
//
//  Exists because onboarding is not a route back. `hasCompletedOnboarding` is
//  durable, so once a teacher finishes or skips the walkthrough the account
//  step is gone unless they deliberately replay it from Settings → About — and
//  nobody looks for "sign in" under "About". This wraps the same `AccountStep`
//  in its own sheet so signing in is one click from where a teacher would
//  actually look for it.
//
//  Deliberately reuses `AccountStep` rather than restating the form. Two copies
//  of a sign-in screen drift, and the one that drifts is always the one nobody
//  is looking at.
//

import SwiftUI

struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var accounts = AccountStore.shared

    /// Set once the sheet has seen a signed-in state, so the auto-dismiss below
    /// fires on the *transition* into signed-in rather than immediately when a
    /// teacher opens the sheet while already signed in — which would make the
    /// window flash open and shut.
    @State private var wasSignedIn = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Anchor account")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider().overlay(Theme.hairline)

            ScrollView(.vertical) {
                AccountStep()
                    .padding(24)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 480, height: 560)
        .background(.background)
        .onAppear { wasSignedIn = accounts.isSignedIn }
        .onChange(of: accounts.isSignedIn) { _, isSignedIn in
            // Close on the way in, never on the way out: signing out from
            // inside this sheet should leave the form on screen so the teacher
            // can sign in as somebody else.
            guard isSignedIn, !wasSignedIn else {
                wasSignedIn = isSignedIn
                return
            }
            wasSignedIn = true
            dismiss()
        }
    }
}

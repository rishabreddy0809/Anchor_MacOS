//
//  SignedOutGate.swift
//  Anchor
//
//  What the window shows when nobody is signed in.
//
//  An Anchor account is not optional. It is what a subscription attaches to, so
//  a copy of Anchor nobody has signed into is a copy nobody is paying for, and
//  the account step being skippable made that a matter of pressing "Skip" once.
//  Onboarding alone could never enforce it either: `hasCompletedOnboarding` is
//  durable, so a teacher who signed in on Monday and signed out on Friday would
//  never see the walkthrough again and would keep full use of the app. The gate
//  therefore lives on the window rather than in the walkthrough.
//
//  **It is dormant in a build where accounts cannot work.** `isConfigured` is
//  false when FirebaseAuth is absent or `GoogleService-Info.plist` is missing,
//  and in that state there is no way on earth to satisfy the gate — so gating
//  would not protect a subscription, it would brick the app for everyone
//  including whoever is building it. Same reasoning the onboarding step already
//  used, applied one level up. The moment the plist lands, this becomes real
//  with no further change.
//
//  Nothing is destroyed by being locked out. Sessions, rosters and scores are
//  on the teacher's Mac and stay there; signing back in returns the app exactly
//  as it was. That is worth saying on screen, because "sign in to continue" on
//  an app holding months of a teacher's classes otherwise reads as a threat.
//

import SwiftUI

struct SignedOutGate: View {
    @ObservedObject private var accounts = AccountStore.shared

    @State private var isPresentingSignIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.13))
                        .frame(width: 78, height: 78)
                    AnchorGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34)
                }

                VStack(spacing: 7) {
                    Text("Sign in to use Anchor")
                        .font(.system(size: 21, weight: .semibold))

                    Text("Anchor needs an account. It holds your name and email and "
                         + "nothing about your classes.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                }

                Button("Sign in or create an account") { isPresentingSignIn = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                // The reassurance is the point, not decoration. A teacher who
                // has been using Anchor for a term is looking at a screen that
                // has replaced their classes, and the first question is whether
                // those are gone.
                Text("Your classes, rosters and session history stay on this Mac. "
                     + "Signing in brings them straight back.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $isPresentingSignIn) {
            SignInSheet()
        }
    }
}

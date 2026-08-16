//
//  QuickInfoCard.swift
//  Anchor
//
//  A small identity card for the open student. Only shows email today —
//  advisor and enrollment date aren't tracked by any data source Anchor has
//  (no SIS, no advisor roster), so the card doesn't render placeholders for
//  them rather than showing something that isn't real.
//

import SwiftUI

struct QuickInfoCard: View {
    let student: Student

    var body: some View {
        if let email {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick info")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text("Email")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    if let mailURL = URL(string: "mailto:\(email)") {
                        Link(email, destination: mailURL)
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        Text(email)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    /// The verified Zoom address where there is one, else the Classroom roster
    /// address for a student matched by name.
    private var email: String? {
        let prefix = "email:"
        if student.identityKey.hasPrefix(prefix) {
            return String(student.identityKey.dropFirst(prefix.count))
        }
        return student.academic?.email
    }
}

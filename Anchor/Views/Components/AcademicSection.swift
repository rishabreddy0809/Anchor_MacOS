//
//  AcademicSection.swift
//  Anchor
//
//  The ACADEMIC (Classroom) half of the student detail view, plus the score
//  breakdown that shows how much of a number came from the model and how much
//  from the academic rules.
//
//  The split is the point. A teacher acting on "92%" deserves to know that 87 of
//  it was measured from the meeting and 5 was added because coursework is
//  missing — those are different kinds of claim with different reliability.
//

import SwiftUI

// MARK: - Score breakdown

/// Model score, academic adjustment, and the total — shown only when the rule
/// layer actually fired.
struct ScoreBreakdownCard: View {
    let student: Student
    let level: RiskLevel

    var body: some View {
        if let escalation = student.academicEscalation, escalation.didEscalate {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Score breakdown", trailingText: student.scoreSource.label)

                VStack(spacing: 7) {
                    row(
                        label: "Engagement model (Zoom)",
                        value: "\(Int((escalation.baseScore * 100).rounded()))%",
                        tint: .secondary
                    )

                    ForEach(escalation.factors) { factor in
                        row(
                            label: factor.title,
                            value: factor.signedPoints,
                            // Green for the lines that lowered the score. Shown
                            // in the same list rather than a separate one: this
                            // is the arithmetic behind the number above it, and
                            // hiding the subtractions would leave a total the
                            // teacher couldn't reconcile.
                            tint: {
                                switch factor.severity {
                                case .high: Theme.riskHigh
                                case .medium: Theme.riskElevated
                                case .reassuring: Theme.riskLow
                                }
                            }(),
                            isIndented: true,
                            caption: factor.severity.label
                        )
                    }

                    Divider().overlay(Theme.hairline)

                    row(
                        label: "Total",
                        value: student.scoreDisplay,
                        tint: level.color,
                        isBold: true
                    )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Theme.surface)
                )

                // The provenance warning. Without it the combined number would
                // read as a single model prediction, which it is not.
                Text("The engagement score is a model prediction. The academic "
                     + "additions are fixed rules, applied because the current model "
                     + "was trained before Classroom data was available.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(
        label: String,
        value: String,
        tint: Color,
        isIndented: Bool = false,
        isBold: Bool = false,
        caption: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            if isIndented {
                Circle()
                    .fill(tint)
                    .frame(width: 4, height: 4)
                    .padding(.leading, 6)
            }

            Text(label)
                .font(.system(size: 11, weight: isBold ? .semibold : .regular))
                .foregroundStyle(isIndented ? .secondary : .primary)
                .lineLimit(1)

            if let caption {
                Text("(\(caption))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: isBold ? 13 : 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Academic panel

/// ACADEMIC (Classroom): missing work, grade trend, last submission.
struct AcademicSection: View {
    let student: Student
    @ObservedObject private var classroom = ClassroomViewModel.shared
    /// Observed directly as well as through the view model: the connection state
    /// lives here, and this panel must not render a stale "not connected".
    @ObservedObject private var credentials = GoogleCredentialsStore.shared
    /// The Zoom side of identity. When this panel says a student is matched by
    /// name, the reason no address was available is here and nowhere else the
    /// teacher can reach.
    @ObservedObject private var zoom = ZoomViewModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(
                text: "Academic (Classroom)",
                trailingText: classroom.activeCourse?.name
            )

            if let snapshot = student.academic, !snapshot.isEmpty {
                populated(snapshot)
            } else {
                unavailable
            }

            if classroom.isConnected, classroom.isMonitoringAnyCourse {
                linkControl
            }
        }
    }

    // MARK: Manual link

    /// Lets the teacher say who this participant is when Anchor won't guess.
    ///
    /// This is the only route to academic data for a student Zoom can't identify
    /// and whose name is shared — the derived rules refuse both on purpose, and
    /// a person who can see the room is better evidence than either.
    private var linkControl: some View {
        HStack(spacing: 6) {
            if let match = currentMatch, match.isManual {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("You linked this participant to \(match.student.name).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Menu {
                ForEach(sortedRoster, id: \.id) { candidate in
                    Button(candidate.name.isEmpty ? "Unnamed student" : candidate.name) {
                        classroom.linkParticipant(
                            identityKey: student.identityKey,
                            name: student.name,
                            to: candidate,
                            isDurable: !hasNameTwinInMeeting
                        )
                    }
                }

                if currentMatch?.isManual == true {
                    Divider()
                    Button("Remove link", role: .destructive) {
                        classroom.unlinkParticipant(
                            identityKey: student.identityKey,
                            name: student.name
                        )
                    }
                }
            } label: {
                Text(currentMatch?.isManual == true ? "Change" : "Link to student…")
                    .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(sortedRoster.isEmpty)
        }
    }

    private var currentMatch: AcademicMatchTable.Match? {
        classroom.rosterMatch(forIdentity: student.identityKey, name: student.name)
    }

    /// Everyone the teacher could be pointing at: this meeting's class when it
    /// has been linked to one, otherwise every monitored class's roster.
    private var sortedRoster: [ClassroomStudent] {
        let roster = classroom.activeCourse
            .map { classroom.rosters[$0.id] ?? [] }
            ?? classroom.monitoredRoster
        return roster.sorted { $0.name < $1.name }
    }

    /// True when someone else in this meeting answers to the same name.
    ///
    /// Such a link can't be remembered for next week — the name key would
    /// resolve to both people — so it is kept for this meeting only.
    private var hasNameTwinInMeeting: Bool {
        guard let key = ClassroomNameKey.make(student.name) else { return true }
        return EngagementStore.shared.students
            .filter { ClassroomNameKey.make($0.name) == key }
            .count > 1
    }

    // MARK: Populated

    private func populated(_ snapshot: AcademicSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
                spacing: 7
            ) {
                MetricTile(
                    symbolName: "doc.badge.ellipsis",
                    value: "\(snapshot.missingCount)",
                    caption: "Missing",
                    tint: snapshot.missingCount > 0 ? Theme.riskHigh : .secondary
                )
                MetricTile(
                    symbolName: "chart.line.uptrend.xyaxis",
                    value: snapshot.gradeTrendDisplay,
                    caption: "Grade trend",
                    tint: trendTint(snapshot)
                )
                MetricTile(
                    symbolName: "clock.arrow.circlepath",
                    value: snapshot.lastSubmissionDisplay,
                    caption: "Last submission"
                )
                MetricTile(
                    symbolName: "percent",
                    value: snapshot.averageGradeDisplay,
                    caption: "Grade average",
                    tint: averageTint(snapshot)
                )
                MetricTile(
                    symbolName: "exclamationmark.arrow.circlepath",
                    value: "\(snapshot.lateCount)",
                    caption: "Late",
                    tint: snapshot.lateCount > 0 ? Theme.riskElevated : .secondary
                )
                MetricTile(
                    symbolName: "checkmark.seal",
                    value: "\(snapshot.gradedCount)",
                    caption: "Graded"
                )
            }

            if !snapshot.missingAssignments.isEmpty {
                missingList(snapshot)
            }

            if snapshot.gradedCount > 0, snapshot.gradeTrend == nil {
                // Explain a blank trend rather than leaving an em dash. Four
                // graded assignments is the floor — see AcademicRollup.trend.
                Text("Not enough graded work yet to read a grade trend "
                     + "(\(snapshot.gradedCount) of 4 needed).")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The caveat matters most exactly here, where real grades are on
            // screen under a name Zoom never verified.
            if let match = currentMatch, match.needsCaveat {
                Label(
                    "Matched to \(snapshot.name) by display name — Zoom reported no "
                    + "email for this participant, so this pairing is unverified.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func missingList(_ snapshot: AcademicSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Missing assignments")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(snapshot.missingAssignments.prefix(5)) { assignment in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "circle")
                        .font(.system(size: 7))
                        .foregroundStyle(Theme.riskHigh)
                        .padding(.top, 3)

                    Text(assignment.title)
                        .font(.system(size: 11))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let due = assignment.dueDate {
                        Text("due \(Theme.shortDateString(due))")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if snapshot.missingAssignments.count > 5 {
                Text("+ \(snapshot.missingAssignments.count - 5) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: Unavailable

    /// Why there's no academic data — the reasons need different actions, so
    /// they are never collapsed into one generic message.
    private var unavailable: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: reason.symbol)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(reason.title)
                    .font(.system(size: 11.5, weight: .medium))
                Text(reason.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if reason.showsSettingsLink {
                SettingsLink {
                    Text("Connect")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private struct Reason {
        var symbol: String
        var title: String
        var detail: String
        var showsSettingsLink: Bool
    }

    /// How the roster reads back to the teacher when a name didn't match.
    ///
    /// Naming the students is the whole diagnosis in a small class — "doesn't
    /// match any of the 1 students" hides that the roster says "Rishab Paili"
    /// and Zoom says "Rishab Reddy Paili". Big classes fall back to a count,
    /// where a full list would be unreadable rather than informative.
    private var rosterNames: String {
        let roster = classroom.activeCourse
            .map { classroom.rosters[$0.id] ?? [] }
            ?? classroom.monitoredRoster
        guard !roster.isEmpty, roster.count <= 6
        else { return "any of the \(classroom.monitoredRosterCount) students" }

        let names = roster.map { "“\($0.name)”" }
        guard names.count > 1 else { return names[0] }
        return names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
    }

    /// What to call the class in this panel's copy: the class this meeting was
    /// linked to where there is one, and "your N monitored classes" where the
    /// meeting could belong to any of them.
    private var courseLabel: String { classroom.activeCourseLabel }

    /// The address Zoom reported, or nil when it reported none.
    private var zoomEmail: String? {
        let prefix = "email:"
        guard student.identityKey.hasPrefix(prefix) else { return nil }
        return String(student.identityKey.dropFirst(prefix.count))
    }

    private var reason: Reason {
        guard classroom.isConnected else {
            return Reason(
                symbol: "link.badge.plus",
                title: "Google Classroom not connected",
                detail: "Connect Classroom to factor missing assignments and grade "
                    + "trends into this student's score.",
                showsSettingsLink: true
            )
        }

        guard classroom.isMonitoringAnyCourse else {
            return Reason(
                symbol: "books.vertical",
                title: "No class monitored",
                detail: "Pick the Classroom classes Anchor should sync coursework from — "
                    + "on Home, or in Settings.",
                showsSettingsLink: true
            )
        }

        // Roster membership is the match. Coursework is what gets *reported*
        // once matched, and its absence is a separate fact with a separate fix.
        if let match = classroom.rosterMatch(
            forIdentity: student.identityKey,
            name: student.name
        ) {
            let who = match.student.name.isEmpty
                ? (zoomEmail ?? student.name)
                : match.student.name

            // How the link was made leads every sentence below: an email match
            // is proof of identity, a name match is a reasonable guess, and a
            // teacher acting on grades deserves to know which one they have.
            let provenance: String
            switch match {
            case .manual:
                provenance = "You linked this participant to \(match.student.name)"
                    + (hasNameTwinInMeeting
                        ? " for this meeting — another participant answers to the same "
                            + "name, so the link isn't kept for next week."
                        : ", and Anchor will reapply it in future classes.")
            case .verified:
                provenance = "Matched on \(zoomEmail ?? match.student.email ?? "email")."
            case .byName where zoomEmail == nil:
                provenance = "Matched on the name “\(student.name)” — Zoom reported no "
                    + "email address for this participant, so this link is unverified."
                    + (zoom.emailVerification.studentClause.map { " (\($0))" } ?? "")
            case .byName:
                provenance = "Matched on the name “\(student.name)” — Google didn't share "
                    + "an address for anyone on this roster, so there was none to check "
                    + "\(zoomEmail ?? "their Zoom address") against and this link is "
                    + "unverified."
            }

            if !classroom.canReadCoursework {
                return Reason(
                    symbol: "lock",
                    title: "Linked to \(who)",
                    detail: "\(provenance) Google didn't grant permission to read "
                        + "\(courseLabel)'s assignments or grades, so there's no "
                        + "coursework to show.",
                    showsSettingsLink: true
                )
            }

            guard classroom.lastSyncedAt != nil else {
                return Reason(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Linked to \(who)",
                    detail: "\(provenance) Waiting for the first coursework sync "
                        + "of \(courseLabel).",
                    showsSettingsLink: false
                )
            }

            // Reachable only on a name match: coursework rollups are keyed by
            // the roster address, so a student Google gave no email for has no
            // rollup to show even though the person is identified.
            guard match.student.matchKey != nil else {
                return Reason(
                    symbol: "envelope.badge",
                    title: "Linked to \(who)",
                    detail: "\(provenance) Google didn't share this student's email "
                        + "address for \(courseLabel), and coursework is filed under it — "
                        + "grant the profile-email permission to see their assignments.",
                    showsSettingsLink: true
                )
            }

            return Reason(
                symbol: "checkmark.circle",
                title: "Linked to \(who)",
                detail: "\(provenance) Nothing overdue and nothing graded yet in "
                    + "\(courseLabel), so there's no academic signal to add to this "
                    + "student's score.",
                showsSettingsLink: false
            )
        }

        // Past here, neither route found anyone: no roster address matches, and
        // the display name matched no one either (or matched two people, which
        // the table refuses on purpose).
        guard let email = zoomEmail else {
            let rosterSize = classroom.monitoredRosterCount
            return Reason(
                symbol: "person.crop.circle.badge.questionmark",
                title: "Not linked to Classroom",
                detail: (zoom.emailVerification.studentClause.map {
                    "Zoom reported no email address for this participant — \($0) "
                } ?? "Zoom reported no email address for this participant — they "
                    + "joined as a guest, or Zoom withholds it for anyone outside your "
                    + "account. ")
                    + "Anchor fell back to their display name, and “\(student.name)” "
                    + (rosterSize > 0
                        ? "doesn't match \(rosterNames) on the \(courseLabel) roster. "
                            + "Ask them to rename themselves in Zoom to the name their "
                            + "school uses."
                        : "can't be checked because no roster has loaded for \(courseLabel) yet."),
                showsSettingsLink: rosterSize == 0
            )
        }

        // The connected Google account is the *teacher*, and Classroom's roster
        // endpoint returns students only — so the teacher sitting in their own
        // Zoom meeting can never match, and "isn't on the roster" would read as
        // a fault rather than as the definition of the word.
        if let account = credentials.tokens?.accountEmail,
           account.trimmed.lowercased() == email {
            return Reason(
                symbol: "person.crop.circle.badge.checkmark",
                title: "This is your own account",
                detail: "\(email) is the Google account Anchor is signed in with. Teachers "
                    + "aren't on their class's student roster, so there's no coursework "
                    + "to show against them.",
                showsSettingsLink: false
            )
        }

        // Unmatched. Both addresses are named — the mismatch is almost always a
        // school account on one side and a personal one on the other, and that
        // is impossible to spot from "their Zoom email differs".
        let rosterSize = classroom.monitoredRosterCount
        guard rosterSize > 0 else {
            return Reason(
                symbol: "person.crop.circle.badge.questionmark",
                title: "Roster not loaded",
                detail: "Anchor holds no roster for \(courseLabel) yet, so it can't match "
                    + "\(email). Reload your classes from Home, and check that Google "
                    + "granted the rosters and profile-email permissions.",
                showsSettingsLink: true
            )
        }

        return Reason(
            symbol: "person.crop.circle.badge.questionmark",
            title: "No match in this course",
            detail: "Zoom reports \(email) for \(student.name), and none of the "
                + "\(rosterSize) students on the \(courseLabel) roster has that address — "
                + "usually a personal Zoom account against a school Classroom one. Anchor "
                + "won't fall back to the display name here: an address that doesn't "
                + "match is evidence of a different person, and a shared name doesn't "
                + "outweigh it. Ask them to join Zoom from their school account.",
            showsSettingsLink: false
        )
    }

    // MARK: Tints

    private func trendTint(_ snapshot: AcademicSnapshot) -> Color {
        guard let trend = snapshot.gradeTrend else { return .secondary }
        if trend <= -0.15 { return Theme.riskHigh }
        if trend <= -0.05 { return Theme.riskElevated }
        if trend >= 0.05 { return Theme.riskLow }
        return .secondary
    }

    private func averageTint(_ snapshot: AcademicSnapshot) -> Color {
        guard let average = snapshot.averageGrade else { return .secondary }
        if average < 0.60 { return Theme.riskHigh }
        if average < 0.75 { return Theme.riskElevated }
        return Theme.riskLow
    }
}

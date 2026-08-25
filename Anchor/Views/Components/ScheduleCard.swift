//
//  ScheduleCard.swift
//  Anchor
//
//  Today's teaching, from the teacher's own calendar.
//
//  Placed on the dashboard because the dashboard's weakest moment is when no
//  class is running: `DashboardView` falls through to `EmptyStateView`, which
//  is honest and says nothing a teacher can use. Between classes is most of a
//  teaching day, and "AP Biology in 12 minutes" is the one thing worth showing
//  then.
//
//  Every title here is the teacher's own calendar data. It renders on their Mac
//  and goes nowhere — see CalendarService for the rules this view is downstream
//  of, in particular that none of it is ever logged.
//

import SwiftUI

struct ScheduleCard: View {

    @ObservedObject private var calendar = CalendarService.shared

    /// Where "connect your calendar" should send the teacher. Nil hides the
    /// invitation entirely, for surfaces that should never prompt.
    var onConnect: (() -> Void)?

    /// Injected so the view is testable and so previews are not at the mercy of
    /// the wall clock.
    var now: Date = Date()

    var body: some View {
        if calendar.isConfigured {
            configured
        } else if onConnect != nil {
            invitation
        }
    }

    // MARK: - Configured

    private var configured: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Today")

            VStack(alignment: .leading, spacing: 7) {
                if let current = calendar.current(at: now) {
                    row(current, kind: .now)
                }
                if let next = calendar.next(at: now) {
                    row(next, kind: .next)
                }
                if calendar.current(at: now) == nil && calendar.next(at: now) == nil {
                    Text(calendar.today.isEmpty
                         ? "Nothing on your calendar today."
                         : "That's everything for today.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    private enum RowKind { case now, next }

    private func row(_ event: ScheduledClass, kind: RowKind) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // A filled dot for what is running, hollow for what is coming, so
            // the two are distinguishable without reading the label.
            Circle()
                .fill(kind == .now ? Theme.riskLow : Color.clear)
                .overlay(Circle().strokeBorder(kind == .now ? Color.clear : Theme.hairline, lineWidth: 1.5))
                .frame(width: 7, height: 7)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Text(event.timeRange)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(label(for: event, kind: kind))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(kind == .now ? Theme.riskLow : Theme.accent)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// "Now", or how long until it starts.
    ///
    /// Minutes up to an hour, then hours — "in 143 minutes" is a number a
    /// teacher has to do arithmetic on, which is the opposite of the point.
    private func label(for event: ScheduledClass, kind: RowKind) -> String {
        guard kind == .next else { return "Now" }
        let minutes = event.minutesUntilStart(from: now)
        if minutes <= 0 { return "Starting" }
        if minutes < 60 { return "in \(minutes) min" }
        let hours = Int((Double(minutes) / 60).rounded())
        return hours == 1 ? "in 1 hour" : "in \(hours) hours"
    }

    // MARK: - Not configured

    private var invitation: some View {
        Button {
            onConnect?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connect your calendar")
                        .font(.system(size: 11.5, weight: .medium))
                    Text(subtitleForInvitation)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
        .buttonStyle(.plain)
    }

    /// Names which half is missing. "Denied" and "granted but no calendar
    /// chosen" look identical on screen and are fixed in completely different
    /// places — one in System Settings, one in Anchor's.
    private var subtitleForInvitation: String {
        switch calendar.access {
        case .granted:
            "Choose which calendars to show in Settings."
        case .denied:
            "Calendar access is off for Anchor in System Settings → Privacy."
        case .notDetermined:
            "See what you're teaching next, right here."
        }
    }
}

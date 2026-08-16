//
//  RootPopoverView.swift
//  Anchor
//
//  Fixed-size shell hosted by the NSPopover. Owns the header/footer chrome and
//  animates between routes.
//

import SwiftUI

struct RootPopoverView: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var router: PopoverRouter
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var monitor = MeetingMonitorCoordinator.shared

    /// Set by the AppKit layer so the × button can dismiss the popover.
    var closeAction: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                switch router.route {
                case .dashboard:
                    DashboardView()
                        .transition(transition)
                case .allStudents:
                    AllStudentsView()
                        .transition(transition)
                case .detail(let id):
                    StudentDetailView(studentID: id)
                        .transition(transition)
                case .settings:
                    SettingsView()
                        .transition(transition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: router.route)

            footer
        }
        .frame(width: Theme.popoverWidth, height: Theme.popoverHeight)
        .background(.regularMaterial)
    }

    // MARK: - Chrome

    private var header: some View {
        PopoverHeader(
            title: headerTitle,
            subtitle: headerSubtitle,
            backAction: router.canGoBack ? { router.pop() } : nil
        ) {
            HStack(spacing: 2) {
                if router.route != .settings {
                    ToolbarIconButton(systemName: "gearshape.fill", help: "Settings") {
                        router.push(.settings)
                    }
                }
                ToolbarIconButton(systemName: "xmark", help: "Close", action: closeAction)
            }
        }
    }

    private var footer: some View {
        PopoverFooter(
            leadingText: "Last updated: \(store.lastUpdatedDescription)",
            trailingText: footerTrailing,
            refreshAction: { Task { await zoom.refreshNow() } }
        )
    }

    // MARK: - Titles

    private var headerTitle: String {
        if case .detail(let id) = router.route, let student = store.student(id: id) {
            return student.name
        }
        return router.route.title
    }

    private var headerSubtitle: String? {
        switch router.route {
        case .dashboard:
            // "🟢 Monitoring Math 101" once the bot is in.
            return monitor.headerStatus
        case .allStudents:
            return "\(store.students.count) in \(store.meetingTitle)"
        case .detail(let id):
            guard let student = store.student(id: id) else { return nil }
            return "\(store.risk(for: student).label) · \(store.meetingTitle)"
        case .settings:
            return "Anchor preferences"
        }
    }

    private var footerTrailing: String? {
        switch router.route {
        case .settings:
            return nil
        default:
            let count = store.highRiskCount
            return count == 0 ? "No high risk" : "\(count) high risk"
        }
    }

    // MARK: - Transitions

    private var transition: AnyTransition {
        let isForward = router.direction == .forward
        return .asymmetric(
            insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

#Preview {
    let store = EngagementStore()
    return RootPopoverView()
        .environmentObject(store)
        .environmentObject(PopoverRouter())
        .environmentObject(LiveCoachViewModel.shared)
}

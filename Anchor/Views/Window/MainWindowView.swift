//
//  MainWindowView.swift
//  Anchor
//
//  The window shell. Four tabs:
//
//    Home     — your classes and their history, the half of Anchor that
//               outlives a meeting. This is what the window opens on.
//    Live     — the running class: roster, scores, drill-down.
//    Insights — every monitored class's roster in one place, ranked by
//               coursework standing, drilling into the same per-student
//               history CourseDetailView's own cards open.
//    Settings — the same panels the ⌘, window shows, now reachable without
//               leaving the main window.
//
//  Home is the landing tab because most of the time there is no class running,
//  and "what happened in my classes" is a better answer to an empty window than
//  "not connected". When a class does connect, the window switches itself to
//  Live so the teacher lands where the action is.
//
//  The menu bar popover is unaffected — it shares EngagementStore with this
//  window and keeps showing the live session regardless of which tab is open.
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var onboarding = OnboardingStore.shared
    @ObservedObject private var accounts = AccountStore.shared

    enum Tab: Hashable {
        case home
        case live
        case insights
        case settings
    }

    @State private var tab: Tab = .home
    /// True once the window has auto-switched for the current class, so a
    /// teacher who deliberately goes back to Home mid-lesson is left there
    /// instead of being pulled to Live on every refresh.
    @State private var hasAutoSwitched = false

    /// No account, no app. See SignedOutGate for why this is on the window
    /// rather than in onboarding, and why it is dormant when accounts cannot
    /// work at all.
    private var requiresSignIn: Bool { accounts.requiresSignIn }

    var body: some View {
        Group {
            if requiresSignIn {
                SignedOutGate()
            } else {
                tabs
            }
        }
        // Onboarding still presents over the gate on a first run, so a new
        // teacher meets the walkthrough rather than a locked window.
        .sheet(isPresented: $onboarding.isPresented) {
            OnboardingView()
                .environmentObject(store)
                .environmentObject(zoom)
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeView(onOpenLive: { tab = .live }, onOpenSettings: { tab = .settings })
                .tabItem { Label("Home", systemImage: "square.grid.2x2") }
                .tag(Tab.home)

            LiveSessionView()
                .tabItem { Label("Live Class", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.live)
                .badge(store.settings.showsBadge ? store.highRiskCount : 0)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.insights)

            SettingsTabView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // One clock for the whole window: the Live tab's relative times and
        // Home's elapsed counter both depend on it, and it must keep running
        // while either is on screen.
        .onAppear {
            store.addTickObserver()
#if DEBUG
            // Screenshot mode picks its own tab and keeps it: `hasAutoSwitched`
            // is pre-armed so the live-class switch below cannot pull the
            // window off the Settings pane part-way through a capture.
            if DemoData.isEnabled {
                hasAutoSwitched = true
                switch DemoData.view {
                case .settings: tab = .settings
                case .insights, .history: tab = .insights
                case .home: tab = .home
                // .popover leaves the window on Live; the capture is of the
                // menu bar popover, which is a separate window entirely.
                case .overview, .student, .popover: tab = .live
                }
                return
            }
#endif
            onboarding.presentIfNeeded()
        }
        .onDisappear { store.removeTickObserver() }
        .onChange(of: store.hasData) { _, hasData in
            guard hasData else {
                // Class over — arm the switch again for the next one. The tab is
                // deliberately left where it is rather than yanked back to Home
                // while the teacher may still be reading a student.
                hasAutoSwitched = false
                return
            }
            guard !hasAutoSwitched else { return }
            hasAutoSwitched = true
            withAnimation(.easeInOut(duration: 0.25)) { tab = .live }
        }
        .sheet(
            isPresented: Binding(
                get: { zoom.isLessonTopicPromptPresented },
                set: { presented in
                    if !presented { zoom.dismissLessonTopicPrompt() }
                }
            )
        ) {
            LessonTopicPrompt()
                .environmentObject(zoom)
        }
    }
}

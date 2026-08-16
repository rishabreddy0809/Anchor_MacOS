//
//  LiveSessionView.swift
//  Anchor
//
//  The live tab: roster sidebar on the left, class overview or student
//  drill-down on the right. Shares EngagementStore with the menu bar popover,
//  so both views always agree.
//
//  Was `MainWindowView` before the window gained tabs; the shell that hosts it
//  now lives there instead.
//

import SwiftUI

struct LiveSessionView: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var zoom: ZoomViewModel
    @ObservedObject private var monitor = MeetingMonitorCoordinator.shared

    /// The sidebar always has a selection on macOS, so the class overview is an
    /// explicit item rather than "nothing selected" — otherwise it would be
    /// unreachable once a student is picked.
    enum SidebarSelection: Hashable {
        case overview
        case student(UUID)
    }

#if DEBUG
    @State private var selection: SidebarSelection? = {
        guard DemoData.view == .student, let id = DemoData.topStudentID else { return .overview }
        return .student(id)
    }()
#else
    @State private var selection: SidebarSelection? = .overview
#endif
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 275, max: 340)
        } detail: {
            Group {
                if case .student(let id) = selection, let student = store.student(id: id) {
                    StudentDetailView(studentID: student.id)
                        .frame(maxWidth: 620, alignment: .top)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ClassOverviewView { selection = .student($0) }
                }
            }
            .frame(minWidth: 420)
        }
        .navigationTitle(store.meeting?.displayName ?? "Anchor")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
    }

    private var subtitle: String {
        if let status = monitor.headerStatus, !store.hasData {
            return status
        }
        guard store.hasData else {
            return store.connectionSummary ?? zoom.state.label
        }
        if let status = monitor.headerStatus, monitor.phase.isMonitoring {
            return "\(status) · \(store.students.count) students"
        }
        let elapsed = Theme.elapsedString(store.elapsed)
        return "\(elapsed) elapsed · \(store.highRiskCount) high risk · \(store.students.count) students"
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            SidebarBrandingHeader()

            List(selection: $selection) {
                Label("Class Overview", systemImage: "square.grid.2x2")
                    .font(.system(size: 12, weight: .medium))
                    .tag(SidebarSelection.overview)

                Section(store.hasData ? "Roster" : "No students") {
                    ForEach(filteredStudents) { student in
                        SidebarStudentRow(
                            student: student,
                            level: store.risk(for: student),
                            now: store.now
                        )
                        .tag(SidebarSelection.student(student.id))
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 6) {
                RiskDot(level: .high, size: 6)
                Text("\(store.highRiskCount)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                RiskDot(level: .elevated, size: 6)
                Text("\(store.elevatedCount)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                RiskDot(level: .low, size: 6)
                Text("\(store.engagedCount)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())

                Spacer()

                Text("Updated \(store.lastUpdatedDescription.lowercased())")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search students")
    }

    private var filteredStudents: [Student] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.rankedStudents }
        return store.rankedStudents.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                Image(systemName: store.meeting?.platform.symbolName ?? "video.slash")
                    .foregroundStyle(Theme.accent)
                ConnectionStatusChip()
                StatusChip(
                    store.sessionState.isRunning ? "Live" : "Paused",
                    systemImage: store.sessionState.isRunning ? "circle.fill" : "pause.fill",
                    tint: store.sessionState.isRunning ? Theme.riskLow : .secondary
                )
            }
            // The toolbar's own background sits flush against the leading item,
            // so the camera glyph touched the edge of the pill without this.
            .padding(.horizontal, 6)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Text(Theme.elapsedString(store.elapsed))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .help("Time since this session started")

            Button {
                store.toggleSession()
            } label: {
                Label(
                    store.sessionState.isRunning ? "Pause" : "Start",
                    systemImage: store.sessionState.isRunning ? "pause.fill" : "play.fill"
                )
            }
            .help(store.sessionState.isRunning ? "Pause monitoring" : "Resume monitoring")

            Button {
                Task { await zoom.refreshNow() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh now")
            .disabled(!store.dataSource.isLive)

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings")
        }
    }
}

// MARK: - Sidebar row

private struct SidebarStudentRow: View {
    let student: Student
    let level: RiskLevel
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            RiskDot(level: level, isKnown: student.hasReliableScore)

            VStack(alignment: .leading, spacing: 1) {
                Text(student.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(student.statusDescription(now: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(student.scoreDisplay)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(student.hasReliableScore ? level.color : Color.secondary)
        }
        .padding(.vertical, 2)
    }
}

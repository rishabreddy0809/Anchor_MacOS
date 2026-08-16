//
//  AllStudentsView.swift
//  Anchor
//
//  Full roster with search and sorting, reached from "See All Students".
//

import SwiftUI

struct AllStudentsView: View {
    @EnvironmentObject private var store: EngagementStore
    @EnvironmentObject private var router: PopoverRouter

    enum SortOrder: String, CaseIterable, Identifiable {
        case struggle = "Struggle"
        case name = "Name"
        case activity = "Activity"

        var id: String { rawValue }
    }

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .struggle

    var body: some View {
        VStack(spacing: 0) {
            controls

            Divider().overlay(Theme.hairline)

            if filteredStudents.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 1) {
                        ForEach(filteredStudents) { student in
                            StudentRow(
                                student: student,
                                level: store.risk(for: student),
                                now: store.now
                            ) {
                                router.push(.detail(student.id))
                            }
                        }
                    }
                    .padding(.horizontal, Theme.contentPadding)
                    .padding(.vertical, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search students", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.surface)
            )

            Picker("", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.vertical, 9)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No students match \"\(searchText)\"")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var filteredStudents: [Student] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let matched = trimmed.isEmpty
            ? store.students
            : store.students.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }

        switch sortOrder {
        case .struggle:
            return matched.sorted { lhs, rhs in
                if lhs.struggleScore == rhs.struggleScore { return lhs.name < rhs.name }
                return lhs.struggleScore > rhs.struggleScore
            }
        case .name:
            return matched.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .activity:
            return matched.sorted { $0.statusSince > $1.statusSince }
        }
    }
}

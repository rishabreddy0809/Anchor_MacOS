//
//  PopoverRouter.swift
//  Anchor
//
//  Navigation inside the single popover. A tiny stack keeps "back" honest —
//  a student opened from the full roster returns to the roster, not the
//  dashboard.
//

import Combine
import SwiftUI

final class PopoverRouter: ObservableObject {

    enum Route: Hashable {
        case dashboard
        case allStudents
        case detail(UUID)
        case settings

        var title: String {
            switch self {
            case .dashboard: "Anchor Dashboard"
            case .allStudents: "All Students"
            case .detail: "Student Detail"
            case .settings: "Settings"
            }
        }
    }

    enum Direction {
        case forward
        case back
    }

    @Published private(set) var route: Route = .dashboard
    @Published private(set) var direction: Direction = .forward

    private var stack: [Route] = []

    var canGoBack: Bool { !stack.isEmpty }

    func push(_ next: Route) {
        guard next != route else { return }
        direction = .forward
        stack.append(route)
        route = next
    }

    func pop() {
        guard let previous = stack.popLast() else { return }
        direction = .back
        route = previous
    }

    /// Used when the popover closes so it always reopens on the dashboard.
    func resetToRoot() {
        stack.removeAll()
        direction = .back
        route = .dashboard
    }
}

//
//  StatusItemController.swift
//  Anchor
//
//  Owns the NSStatusItem and the NSPopover that hangs off it.
//

import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: EngagementStore
    private let router = PopoverRouter()
    private let badgeView = BadgeDotView()

    private var cancellables = Set<AnyCancellable>()
    private var trackingArea: NSTrackingArea?

    init(store: EngagementStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configurePopover()
        observeStore()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        // Remembers where the teacher ⌘-drags the icon to in the menu bar.
        statusItem.autosaveName = "AnchorStatusItem"

        guard let button = statusItem.button else { return }

        button.image = Self.makeMenuBarIcon()
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Anchor — student engagement"
        button.setAccessibilityLabel("Anchor")

        // The red dot lives in its own layer so the anchor mark can stay a template
        // image and keep tracking the menu bar's light/dark appearance.
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.isHidden = true
        button.addSubview(badgeView)
        NSLayoutConstraint.activate([
            badgeView.widthAnchor.constraint(equalToConstant: BadgeDotView.diameter),
            badgeView.heightAnchor.constraint(equalToConstant: BadgeDotView.diameter),
            badgeView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
            badgeView.topAnchor.constraint(equalTo: button.topAnchor, constant: 4)
        ])

        installTrackingArea(on: button)
    }

    /// The anchor mark, as a template image so macOS tints it for the current
    /// menu bar appearance.
    ///
    /// The same geometry as `AnchorGlyph` in CoreComponents, redrawn here in
    /// AppKit because a SwiftUI `Shape` cannot be handed to `NSStatusItem`.
    /// It used to be the letter "A", which shared nothing with the mark in the
    /// popover header, the sidebar or the app icon — the one piece of Anchor a
    /// teacher sees all day was the one piece that wasn't branded.
    ///
    /// Drawn in a 24-unit space and scaled, so the coordinates below can be
    /// compared line-for-line against `AnchorGlyph.path(in:)`.
    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let s = min(rect.width, rect.height) / 24
            // AppKit's y axis points up and SwiftUI's points down, so the glyph
            // is flipped here rather than being drawn upside down.
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: rect.minX + x * s, y: rect.maxY - y * s)
            }

            let path = NSBezierPath()
            path.lineWidth = 1.7 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // Ring
            let ringRadius = 2 * s
            let ringCenter = pt(12, 4)
            path.appendOval(in: NSRect(
                x: ringCenter.x - ringRadius, y: ringCenter.y - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2
            ))

            // Shaft
            path.move(to: pt(12, 6))
            path.line(to: pt(12, 22))

            // Crossbar
            path.move(to: pt(9, 11))
            path.line(to: pt(15, 11))

            // Flukes: right tick, semicircle through the bottom, left tick.
            path.move(to: pt(19, 13))
            path.line(to: pt(21, 12))
            let steps = 48
            for i in 1...steps {
                let theta = CGFloat(i) / CGFloat(steps) * .pi
                path.line(to: pt(12 + 9 * cos(theta), 12 + 9 * sin(theta)))
            }
            path.line(to: pt(5, 13))

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func installTrackingArea(on button: NSStatusBarButton) {
        if let trackingArea { button.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(area)
        trackingArea = area
    }

    // Tracking-area callbacks are dispatched to the owner by selector, so these
    // are plain @objc methods rather than NSResponder overrides.
    @objc func mouseEntered(with event: NSEvent) {
        guard !popover.isShown else { return }
        statusItem.button?.highlight(true)
    }

    @objc func mouseExited(with event: NSEvent) {
        guard !popover.isShown else { return }
        statusItem.button?.highlight(false)
    }

    // MARK: - Popover

    private func configurePopover() {
        let root = RootPopoverView(closeAction: { [weak self] in self?.closePopover() })
            .environmentObject(store)
            .environmentObject(router)
            .environmentObject(ZoomViewModel.shared)
            .environmentObject(LiveCoachViewModel.shared)

        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: Theme.popoverWidth, height: Theme.popoverHeight)
        popover.behavior = .transient   // closes on click outside
        popover.animates = true
        popover.delegate = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRightClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        router.resetToRoot()
        store.popoverDidOpen()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Deliberately no NSApp.activate here: Anchor is a regular app now, and
        // activating would pull the main window in front of the teacher's Zoom
        // call every time they peek at the menu bar.
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func openSettings() {
        if !popover.isShown { showPopover() }
        router.push(.settings)
    }

    /// Opens the popover on one student — where a tapped recommendation
    /// notification lands.
    ///
    /// `showPopover` resets the router to the dashboard, so the push has to come
    /// after it rather than before.
    func openStudent(id: UUID) {
        if !popover.isShown { showPopover() }
        router.push(.detail(id))
    }

    // MARK: - Right-click menu

    /// Quit lives here, and in Settings.
    ///
    /// This used to reason that an LSUIElement app has no app menu. Anchor is
    /// not one — it runs as a regular app with a Dock icon and a main window, so
    /// there *is* an app menu. The right-click item stays regardless: closing
    /// the window leaves Anchor monitoring from the menu bar (see
    /// `applicationShouldTerminateAfterLastWindowClosed`), so the status item is
    /// often the only part of Anchor still on screen when someone wants to quit.
    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: popover.isShown ? "Close Dashboard" : "Open Dashboard",
            action: #selector(menuTogglePopover),
            keyEquivalent: ""
        ).target = self
        menu.addItem(withTitle: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh Now", action: #selector(menuRefresh), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Anchor", action: #selector(menuQuit), keyEquivalent: "q")
            .target = self

        // Attaching the menu makes the next click open it; detach right after so
        // left-clicks keep toggling the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuTogglePopover() { togglePopover() }
    @objc private func menuOpenSettings() { openSettings() }
    @objc private func menuRefresh() {
        Task { await ZoomViewModel.shared.refreshNow() }
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        store.popoverDidClose()
        router.resetToRoot()
        statusItem.button?.highlight(false)
    }

    // MARK: - Badge

    private func observeStore() {
        // Recompute the badge whenever the roster or the sensitivity changes.
        store.$students
            .combineLatest(store.$settings)
            .sink { [weak self] students, settings in
                guard let self else { return }
                let highRisk = students.filter {
                    $0.risk(sensitivity: settings.sensitivity) == .high
                }.count
                self.updateBadge(count: settings.showsBadge ? highRisk : 0)
            }
            .store(in: &cancellables)
    }

    private func updateBadge(count: Int) {
        let shouldShow = count > 0
        badgeView.isHidden = !shouldShow
        statusItem.button?.setAccessibilityLabel(
            shouldShow ? "Anchor — \(count) students need attention" : "Anchor"
        )
        statusItem.button?.toolTip = shouldShow
            ? "Anchor — \(count) student\(count == 1 ? "" : "s") need attention"
            : "Anchor — student engagement"
    }
}

// MARK: - Badge dot

/// Small red dot drawn over the top-right of the status item.
final class BadgeDotView: NSView {
    static let diameter: CGFloat = 6

    override var allowsVibrancy: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: inset).fill()
    }
}

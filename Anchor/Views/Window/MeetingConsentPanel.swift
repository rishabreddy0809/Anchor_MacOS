//
//  MeetingConsentPanel.swift
//  Anchor
//
//  The "Start monitoring this class?" prompt, as a floating panel rather than a
//  notification.
//
//  ── Why not a notification ──────────────────────────────────────────────────
//
//  It looks better, and that was the ask — but it also fixes two real failures
//  that the notification had and nobody had hit yet, because nobody has run
//  this on a machine that wasn't the developer's.
//
//  1. **Notification authorization is optional and a teacher can decline it.**
//     `MeetingNotifier.isAuthorized` is false until macOS says otherwise, and
//     when it is false `notifyMonitoringPrompt` posts into a void: no prompt,
//     no consent, no bot, and a dashboard that sits at "Ready to monitor"
//     forever with nothing explaining why. A panel is Anchor's own window and
//     needs no permission from anyone.
//
//  2. **A teacher about to teach very likely has a Focus on.** Do Not Disturb
//     suppresses the banner silently — the notification is delivered, and the
//     one moment it mattered has passed. The panel is unaffected.
//
//  The recommendation banners mid-class stay notifications on purpose. Those
//  are transient nudges and a panel for each would sit on top of the lesson.
//  This one is a question that must be answered before anything can happen.
//
//  ── Why the window is configured the way it is ──────────────────────────────
//
//  Every line of `configure()` is load-bearing, and most of them are about a
//  teacher who is *in a full-screen Zoom meeting*, which is the only situation
//  this panel ever appears in.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class MeetingConsentPanelController {

    static let shared = MeetingConsentPanelController()

    private var panel: NSPanel?

    /// Wide enough for a real class name beside two buttons, and close to the
    /// proportions of the Notion and Zoom panels this sits next to.
    ///
    /// 480 was too narrow and truncated *both* lines — including "Anchor joins
    /// as a visible participant", which is the one sentence on this panel that
    /// must not be cut off. The class name may truncate; the disclosure may not.
    static let contentSize = NSSize(width: 620, height: 88)

    private init() {}

    // MARK: - Presentation

    /// Shows the prompt for `meeting`, replacing any panel already on screen.
    func present(
        meeting: DetectedMeeting,
        onAccept: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        dismiss()

        let view = MeetingConsentPanelView(
            meeting: meeting,
            onAccept: { [weak self] in
                self?.dismiss()
                onAccept()
            },
            onDecline: { [weak self] in
                self?.dismiss()
                onDecline()
            }
        )

        // A fixed content size rather than `hosting.fittingSize`. An
        // NSHostingView asked for its fitting size before it has laid out can
        // report a degenerate one, and a zero-sized panel is ordered front
        // perfectly successfully and draws nothing — which looks exactly like
        // the panel never being shown at all.
        let contentSize = Self.contentSize
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.contentView = hosting
        panel.setContentSize(contentSize)
        position(panel)

        // `orderFrontRegardless`, not `makeKeyAndOrderFront`: the teacher is
        // mid-meeting and Anchor must not take focus away from Zoom to ask a
        // question. Combined with `.nonactivatingPanel` the buttons still work
        // on the first click, without the app ever coming forward.
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    var isPresented: Bool { panel != nil }

    // MARK: - Window configuration

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false

        // Above ordinary windows *and* above a full-screen Zoom meeting, which
        // is the only place this is ever seen. `.floating` is not enough: a
        // full-screen app's own window sits above it.
        panel.level = .statusBar

        // `.canJoinAllSpaces` puts it on whichever Space the meeting is on, and
        // `.fullScreenAuxiliary` is what allows it to draw over a full-screen
        // window at all. Without the pair, the panel is posted correctly and
        // the teacher never sees it — the same shape of failure as the
        // suppressed notification this replaces.
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        // Rounded corners and the material come from SwiftUI, so the window
        // itself has to be transparent or they sit on a grey rectangle.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // **Excluded from screen capture.** A teacher who is sharing their
        // screen would otherwise show the whole class a panel reading "Anchor
        // will join as a visible participant and read engagement signals" —
        // about them. The bot being visible in the participant list is a
        // deliberate disclosure; this prompt is addressed to the teacher alone.
        // Same mechanism a password manager uses to stay out of a recording.
        panel.sharingType = .none

        // Nothing here is worth restoring across launches, and a remembered
        // frame would fight `position(_:)` below.
        panel.isRestorable = false
    }

    /// Top-centre of whichever screen the teacher is actually looking at.
    ///
    /// `visibleFrame` rather than `frame` so the panel clears the menu bar and,
    /// on a notched display, the camera housing.
    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 12
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - Content

struct MeetingConsentPanelView: View {

    let meeting: DetectedMeeting
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 34, height: 34)
                AnchorGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Start monitoring \(meeting.name)?")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                // Says the bot is visible before the teacher agrees, not after.
                // "Name the bot out loud" is a positioning decision already
                // taken; this is the screen where it has to hold.
                Text("\(meeting.participantSummary) · Anchor joins as a visible participant")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Button("Not now", action: onDecline)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                // Explicitly filled rather than `.borderedProminent`.
                //
                // This panel is deliberately never the key window — it must not
                // pull focus out of a live Zoom meeting — and AppKit greys a
                // prominent button on an inactive window. The primary action
                // would then look disabled at the one moment it needs to look
                // like the obvious thing to press.
                Button(action: onAccept) {
                    Text("Start")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

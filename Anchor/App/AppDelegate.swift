//
//  AppDelegate.swift
//  Anchor
//
//  Anchor runs as a regular app — dock icon and main window — while also
//  installing the menu bar status item and its popover.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?

#if DEBUG
    /// Sizes the main window as large as its current screen allows, for website
    /// screenshots.
    ///
    /// `screencapture` records a window at its display's backing scale, so a
    /// window on a 1x external display is captured at 1x. Moving it to a Retina
    /// screen would double the pixels, but macOS window restoration puts it
    /// straight back on whichever display it was last used on — so instead of
    /// fighting that, the window is simply grown on the screen it is already
    /// on. At 1800x1040 on a 1080p display that is more pixels than the 1600px
    /// the landing page actually needs.
    /// Retries until SwiftUI has built the window.
    ///
    /// `WindowGroup` creates its window well after
    /// `applicationDidFinishLaunching` returns — measured at more than 1.5s on
    /// this machine, because the Zoom SDK's own panels are constructed first.
    /// A single delayed call therefore found only status-item and Zoom windows
    /// and silently did nothing, leaving the capture to grab a Zoom
    /// certificate panel instead of the app.
    private static func placeWindowForCapture(attempt: Int = 0) {
        guard attempt < 40 else { return }
        guard mainWindow() != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                placeWindowForCapture(attempt: attempt + 1)
            }
            return
        }
        applyCaptureFrame()
    }

    /// The app's own window: titled, and much larger than the status-item
    /// windows or the Zoom SDK's alert panels.
    private static func mainWindow() -> NSWindow? {
        NSApp.windows
            .filter { $0.styleMask.contains(.titled) && $0.contentView != nil }
            .filter { $0.frame.width >= 700 && $0.frame.height >= 400 }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    }

    private static func applyCaptureFrame() {
        guard let window = mainWindow() else { return }

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        guard visible.width > 0 else { return }

        // ANCHOR_DEMO_WINDOW="1400x880" overrides, so the framing can be tuned
        // against a real capture without a rebuild between each attempt.
        var requested = NSSize(width: 1800, height: 1040)
        if let spec = ProcessInfo.processInfo.environment["ANCHOR_DEMO_WINDOW"] {
            let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { requested = NSSize(width: parts[0], height: parts[1]) }
        }

        let size = NSSize(
            width: min(requested.width, visible.width - 40),
            height: min(requested.height, visible.height - 40)
        )
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        window.makeKeyAndOrderFront(nil)
    }
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(store: .shared)
        statusItemController = controller

#if DEBUG
        // Screenshot mode: fabricated classroom, no Zoom, no Google Classroom,
        // no network. Returns before any live data source starts, so nothing
        // can overwrite the demo roster part-way through a capture. See
        // DemoData.swift — compiled out of Release entirely.
        if DemoData.isEnabled {
            EngagementStore.shared.loadDemoData()
            ZoomViewModel.shared.applyDemoConnection()
            // Same reason as profileSubtitle: the captured window must not carry
            // the real name of whoever is signed in on this Mac.
            TeacherProfileStore.shared.applyDemoName(DemoData.teacherName)
            ClassroomViewModel.shared.applyDemoClassroom(
                course: DemoData.course,
                roster: DemoData.roster,
                snapshots: DemoData.courseSnapshots
            )
            SessionArchive.shared.loadDemo(
                classrooms: [DemoData.archiveClassroom],
                sessions: DemoData.archiveSessions
            )
            LiveCoachViewModel.shared.applyDemoTopic()
            NSApp.activate(ignoringOtherApps: true)
            // Re-assert once the window has been built. SwiftUI constructs the
            // scene after this method returns, and something on that path puts
            // the session back to .paused — which renders as a "Paused" chip
            // over a roster that is plainly live. Re-applying after the first
            // runloop turn is enough, and costs nothing outside screenshots.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                EngagementStore.shared.loadDemoData()
                ZoomViewModel.shared.applyDemoConnection()
                Self.placeWindowForCapture()
                // The menu bar popover is its own window; capture mode opens it
                // so it can be photographed by window id rather than cropped
                // out of a desktop screenshot.
                if DemoData.view == .popover {
                    controller.showPopover()
                }
            }
            return
        }
#endif

        // Tapping a recommendation banner opens that student. Wired here rather
        // than inside LiveCoachViewModel because the popover is an AppKit
        // concern the view models deliberately know nothing about.
        MeetingNotifier.shared.onOpenStudent = { [weak controller] id in
            controller?.openStudent(id: id)
        }

        // Load the Core ML struggle model off the main thread now, so the first
        // poll doesn't pay for it while the teacher is waiting on a roster.
        StruggleDetectionService.shared.preload()

        configureDataSource()
        MeetingMonitorCoordinator.shared.start()

        // Pick a previously connected Classroom account back up, so a teacher
        // who connected last term doesn't have to revisit Settings.
        Task { await ClassroomViewModel.shared.restoreIfConnected() }
    }

    /// Delivers `anchor://oauth/…` back to the flow that opened the browser.
    ///
    /// This is the whole reason Info.plist declares a URL scheme: without it a
    /// teacher signs in to Zoom and the browser has nowhere to send them.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            URLSchemeHandler.shared.handle(url)
        }
    }

    /// Switches documented in ZOOM_INTEGRATION.md:
    ///   ANCHOR_NO_AUTOCONNECT=1              don't connect at launch
    ///   ANCHOR_ZOOM_ACCOUNT_ID / _CLIENT_ID / _CLIENT_SECRET
    ///                                        one-shot provisioning into the Keychain
    ///   ANCHOR_ZOOM_OAUTH_CLIENT_ID / _SECRET
    ///                                        ditto, for the browser sign-in app
    private func configureDataSource() {
        let environment = ProcessInfo.processInfo.environment

        seedCredentialsFromEnvironmentIfNeeded(environment)

        // Live by default: if a teacher connected last term, or the deployment
        // provisioned Server-to-Server credentials, pick that back up. If Zoom
        // has nothing for us, the dashboard stays empty and says why.
        guard environment["ANCHOR_NO_AUTOCONNECT"] == nil else { return }
        guard ZoomViewModel.hasAnyZoomCredential else { return }

        // The service built in `init` assumed Server-to-Server credentials,
        // which is the wrong one for a teacher who signed in through the
        // browser. Choose again now that the Keychain has been read.
        ZoomViewModel.shared.useLiveService()
        ZoomViewModel.shared.start()
    }

    /// Lets credentials be provisioned once from the environment instead of
    /// being typed into Settings — useful for a managed deployment. The values
    /// are written to the Keychain and never persisted anywhere else, so the
    /// environment variables are only needed on that first launch.
    private func seedCredentialsFromEnvironmentIfNeeded(_ environment: [String: String]) {
        // The browser sign-in app's own credentials. Separate from the
        // Server-to-Server pair below — different Marketplace app, different
        // purpose — and only needed where OAuthClientDefaults was left blank.
        if let clientID = environment["ANCHOR_ZOOM_OAUTH_CLIENT_ID"], !clientID.isEmpty {
            ZoomOAuthStore.shared.saveClientOverride(
                id: clientID,
                secret: environment["ANCHOR_ZOOM_OAUTH_CLIENT_SECRET"]
            )
        }

        // The Meeting SDK Key/Secret the in-meeting bot signs its JWT with.
        // App-level rather than per-teacher: the key ships in
        // OAuthClientDefaults, so normally only the secret arrives here.
        if environment["ANCHOR_ZOOM_SDK_SECRET"] != nil
            || environment["ANCHOR_ZOOM_SDK_KEY"] != nil {
            MeetingSDKCredentialStore.save(
                key: environment["ANCHOR_ZOOM_SDK_KEY"],
                secret: environment["ANCHOR_ZOOM_SDK_SECRET"]
            )
        }

        guard let accountID = environment["ANCHOR_ZOOM_ACCOUNT_ID"],
              let clientID = environment["ANCHOR_ZOOM_CLIENT_ID"],
              let clientSecret = environment["ANCHOR_ZOOM_CLIENT_SECRET"],
              !accountID.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty
        else { return }

        ZoomCredentialsStore.shared.save(
            ZoomCredentials(
                accountID: accountID,
                clientID: clientID,
                clientSecret: clientSecret
            )
        )
    }

    /// Clicking the dock icon reopens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true
    }

    /// Closing the window leaves Anchor monitoring from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

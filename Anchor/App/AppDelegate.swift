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
    /// being typed into Settings — which in a shipped build is not merely
    /// convenient but the only route, since Settings → Advanced is compiled out
    /// (ship-checklist §4). See ADMIN-SETUP.md step 3.
    ///
    /// The decision about *what* to write lives in `CredentialSeed`, on purpose
    /// and not for tidiness: this function used to read the environment and
    /// write storage in one step, and could not tell an absent variable from an
    /// empty one. Two defects came out of that, both of which only appear on a
    /// partial run — a rotation rather than a first setup. Read
    /// CredentialSeed.swift before changing anything here; the rule is tested
    /// there, and it is tested there because nothing at this layer can be.
    private func seedCredentialsFromEnvironmentIfNeeded(_ environment: [String: String]) {
        let seed = CredentialSeed.read(from: environment)

        // An ordinary double-click names nothing, so it must touch no storage
        // at all — not even to rewrite a value with itself.
        guard !seed.isEmpty else { return }

        ZoomOAuthStore.shared.applyClientOverride(
            id: seed.oauthClientID,
            secret: seed.oauthClientSecret
        )

        // A provisioned client ID with no secret beside it used to be papered
        // over: `effectiveClientID` found no secret and fell through to the
        // *shipped* public client, so Anchor signed the teacher into its own
        // Marketplace app instead of the school's. It no longer does — see
        // `ZoomOAuthConfig.offeredPublicClientID` — which means the visible
        // symptom is now a Connect button that is simply off.
        //
        // That is the honest outcome and it is still a bad one to discover
        // weeks later, so say it here, on stderr, in the Terminal the admin is
        // still looking at. Checked against the *resulting state* rather than
        // against this launch's variables, because rotating only the secret is
        // legitimate and must not be reported as a fault.
        //
        // `operatorMessage` and not `AnchorDiag.log`, which is `#if DEBUG` and
        // would therefore say nothing in the only build anyone provisions.
        if ZoomOAuthStore.shared.clientIDOverride != nil,
           ZoomOAuthStore.shared.clientSecretOverride == nil {
            AnchorDiag.operatorMessage(
                "ANCHOR_ZOOM_OAUTH_CLIENT_ID is provisioned with no "
                    + "ANCHOR_ZOOM_OAUTH_CLIENT_SECRET beside it. Connect Zoom stays off "
                    + "until both are set. Anchor will not fall back to its own Marketplace "
                    + "app here, because a teacher on your account cannot authorize it — "
                    + "they would see \"You cannot authorize\" after approving Anchor."
            )
        }

        // App-level rather than per-teacher: the key ships in
        // OAuthClientDefaults, so normally only the secret arrives here — which
        // is exactly the case that used to delete the key beside it.
        MeetingSDKCredentialStore.apply(key: seed.sdkKey, secret: seed.sdkSecret)

        if let s2s = seed.serverToServer {
            ZoomCredentialsStore.shared.save(
                ZoomCredentials(
                    accountID: s2s.accountID,
                    clientID: s2s.clientID,
                    clientSecret: s2s.clientSecret
                )
            )
        } else if seed.serverToServerIsPartial {
            // The triple authenticates together, so a partial set is refused
            // rather than half-applied. Refusing *silently* is what the old code
            // did, and it is how an admin finishes a setup call believing a
            // value landed.
            //
            // Deliberately not `AnchorDiag.log`, which is `#if DEBUG` and would
            // therefore say nothing in the only build an admin ever provisions.
            // `operatorMessage` writes to stderr, which is attached to the
            // Terminal they ran this from and is where they are still looking.
            AnchorDiag.operatorMessage(
                "Server-to-Server provisioning ignored: ANCHOR_ZOOM_ACCOUNT_ID, "
                    + "ANCHOR_ZOOM_CLIENT_ID and ANCHOR_ZOOM_CLIENT_SECRET must all "
                    + "be supplied together. Nothing was written."
            )
        }
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

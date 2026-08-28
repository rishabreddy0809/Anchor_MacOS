//
//  AnchorApp.swift
//  Anchor
//
//  Created by Rishab Reddy Paili on 7/31/26.
//

import SwiftUI

@main
struct AnchorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The window and the menu bar popover share this one store and view model.
    @ObservedObject private var store = EngagementStore.shared
    @ObservedObject private var zoom = ZoomViewModel.shared
    /// Durable class history, read by the Home tab.
    @ObservedObject private var archive = SessionArchive.shared
    /// Live topic and recommendations, driven by ZoomViewModel's poll loop.
    @ObservedObject private var coach = LiveCoachViewModel.shared

    var body: some Scene {
        WindowGroup("Anchor") {
            MainWindowView()
                .environmentObject(store)
                .environmentObject(zoom)
                .environmentObject(archive)
                .environmentObject(coach)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1020, height: 660)
        .commands { SessionCommands(store: store, zoom: zoom) }

        Settings {
            SettingsWindowView()
                .environmentObject(store)
                .environmentObject(zoom)
                .environmentObject(coach)
        }
    }
}

/// Session controls mirrored into the main menu, so the app behaves like a
/// real Mac app rather than a popover with a window bolted on.
struct SessionCommands: Commands {
    @ObservedObject var store: EngagementStore
    @ObservedObject var zoom: ZoomViewModel

    var body: some Commands {
        CommandMenu("Session") {
            Button(store.sessionState.isRunning ? "Pause Monitoring" : "Start Monitoring") {
                store.toggleSession()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Refresh Now") {
                Task { await zoom.refreshNow() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!store.dataSource.isLive)

            Divider()

            if store.dataSource.isLive {
                Button("Disconnect from Zoom") { zoom.stop() }
            } else {
                Button("Connect to Zoom") { zoom.start() }
                    .disabled(!ZoomViewModel.hasTeacherZoomConnection)
            }
        }
    }
}

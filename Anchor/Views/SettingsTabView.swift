//
//  SettingsTabView.swift
//  Anchor
//
//  Settings, as a tab in the main window rather than only a separate ⌘,
//  window. SettingsView now carries its own sidebar and per-category header,
//  so this just lets it fill the tab's full space.
//

import SwiftUI

struct SettingsTabView: View {
    var body: some View {
        SettingsView()
    }
}

//
//  SettingsWindowView.swift
//  Anchor
//
//  Hosts the shared SettingsView in a standard ⌘, settings window.
//

import SwiftUI

struct SettingsWindowView: View {
    var body: some View {
        SettingsView()
            .frame(width: 760, height: 580)
    }
}

//
//  PopoverChrome.swift
//  Anchor
//
//  Shared header and footer so every route inside the popover lines up.
//

import SwiftUI

struct PopoverHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var backAction: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let backAction {
                ToolbarIconButton(systemName: "chevron.left", help: "Back", action: backAction)
                    .transition(.opacity)
            } else {
                // Only where there's no back chevron: the two together read as
                // two leading glyphs competing for the same corner.
                AnchorGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 13, height: 13)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
    }
}

struct PopoverFooter: View {
    let leadingText: String
    var trailingText: String?
    var refreshAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ConnectionStatusChip()

            Text(leadingText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let refreshAction {
                ToolbarIconButton(
                    systemName: "arrow.clockwise",
                    help: "Refresh now",
                    action: refreshAction
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
    }
}

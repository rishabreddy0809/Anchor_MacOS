//
//  IntegrationCard.swift
//  Anchor
//
//  The Zoom / Google Classroom summary card on Settings → Integrations: icon,
//  what it does, a toggle that connects or disconnects it directly, and a
//  "Connected" badge. Anything more technical than that — client ID
//  overrides, Server-to-Server credentials, the in-meeting bot — lives in the
//  `advanced` content below, collapsed by default so the common case (a
//  teacher checking whether they're connected) stays a glance.
//
//  "Learn more" expands a line of text in place rather than opening a URL —
//  there is no hosted help page for this to link to, and a dead link would be
//  worse than no link.
//

import SwiftUI

struct IntegrationCard<Advanced: View>: View {
    let symbolName: String
    let tint: Color
    let title: String
    let description: String
    let learnMoreDetail: String
    let isConnected: Bool
    let isBusy: Bool
    let canConnect: Bool
    let unavailableReason: String?
    let connectedDetail: String?
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    @ViewBuilder var advanced: () -> Advanced

    @State private var showsDetail = false
    @State private var showsAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    icon

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                        Text(description)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(showsDetail ? "Show less" : "Learn more") {
                            withAnimation(.easeOut(duration: 0.15)) { showsDetail.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 1)

                        if showsDetail {
                            Text(learnMoreDetail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 10)

                    trailing
                }

                if let unavailableReason, !canConnect {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .padding(.top, 1)
                        Text(unavailableReason)
                            .font(.system(size: 10))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.riskElevated)
                }
            }
            .padding(14)

            DisclosureGroup(isExpanded: $showsAdvanced) {
                advanced()
                    .padding(.top, 10)
            } label: {
                Text("Advanced")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.16))
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 46, height: 46)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if isBusy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else {
                Toggle("", isOn: Binding(
                    get: { isConnected },
                    set: { newValue in newValue ? onConnect() : onDisconnect() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.riskLow)
                .controlSize(.small)
                .disabled(!canConnect && !isConnected)
            }

            HStack(spacing: 3) {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 8.5))
                Text(isConnected ? (connectedDetail ?? "Connected") : "Not connected")
                    .font(.system(size: 9.5, weight: isConnected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(isConnected ? Theme.riskLow : Color.secondary)
        }
        .frame(width: 108, alignment: .trailing)
    }
}

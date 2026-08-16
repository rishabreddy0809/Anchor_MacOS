//
//  CoreComponents.swift
//  Anchor
//
//  Small shared building blocks used across the popover views.
//

import SwiftUI

// MARK: - Risk dot

struct RiskDot: View {
    let level: RiskLevel
    var size: CGFloat = 8
    /// False when the score behind this dot is too low-confidence to trust; the
    /// dot renders hollow grey rather than a confident traffic light.
    var isKnown: Bool = true

    var body: some View {
        Group {
            if isKnown {
                Circle()
                    .fill(level.color)
                    .overlay(
                        Circle().strokeBorder(level.color.opacity(0.35), lineWidth: size * 0.4)
                            .scaleEffect(1.9)
                            .opacity(level == .high ? 1 : 0)
                    )
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Avatar

struct Avatar: View {
    let initials: String
    let level: RiskLevel
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(level.color.opacity(0.16))
            Circle()
                .strokeBorder(level.color.opacity(0.35), lineWidth: 1)
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(level.color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Status chip

struct StatusChip: View {
    let text: String
    let systemImage: String?
    let tint: Color
    var filled: Bool = true

    init(_ text: String, systemImage: String? = nil, tint: Color, filled: Bool = true) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.filled = filled
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule().fill(tint.opacity(filled ? 0.14 : 0))
        )
        .overlay(
            Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.35), lineWidth: 1)
        )
    }
}

// MARK: - Sidebar branding

/// Anchor glyph matching the brand mark used on the marketing site (Lucide's
/// "anchor" icon — SF Symbols has no anchor glyph, so the site didn't use one
/// either). Traced from lucide-react's icon node: circle r2 at (12,4), shaft
/// M12 6v16, crossbar M9 11h6, flukes m19 13 2-1 a9 9 0 0 1 -18 0 l2 1.
struct AnchorGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        var path = Path()

        // Ring
        let ringCenter = pt(12, 4)
        let ringRadius = 2 * s
        path.addEllipse(in: CGRect(
            x: ringCenter.x - ringRadius, y: ringCenter.y - ringRadius,
            width: ringRadius * 2, height: ringRadius * 2
        ))

        // Shaft
        path.move(to: pt(12, 6))
        path.addLine(to: pt(12, 22))

        // Crossbar
        path.move(to: pt(9, 11))
        path.addLine(to: pt(15, 11))

        // Flukes: right tick, semicircle, left tick — sampled as a polyline
        // since Path's arc angle/clockwise convention is easy to get backwards.
        // theta 0 → π sweeps (21,12) through the bottom to (3,12), continuing
        // smoothly out of the right tick rather than jumping across first.
        path.move(to: pt(19, 13))
        path.addLine(to: pt(21, 12))
        let steps = 48
        for i in 1...steps {
            let theta = CGFloat(i) / CGFloat(steps) * .pi
            path.addLine(to: pt(12 + 9 * cos(theta), 12 + 9 * sin(theta)))
        }
        path.addLine(to: pt(5, 13))

        return path
    }
}

/// The "⚓ Anchor" wordmark shown at the top of every sidebar, so each pane
/// reads as part of the same app rather than a bare list of items.
struct SidebarBrandingHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            AnchorGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Theme.accent)
                .frame(width: 15, height: 15)
            Text("Anchor")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - Section header

struct SectionLabel: View {
    let text: String
    var trailingText: String?

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(Theme.sectionFont)
                .kerning(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let trailingText {
                Text(trailingText)
                    .font(Theme.captionFont)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Score ring

struct ScoreRing: View {
    let score: Double
    let level: RiskLevel
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6
    /// When false the ring shows "—": the score exists but isn't trustworthy
    /// enough to display as a number.
    var isKnown: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: lineWidth)

            if isKnown {
                Circle()
                    .trim(from: 0, to: max(0.01, min(1, score)))
                    .stroke(
                        level.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.45), value: score)

                VStack(spacing: -1) {
                    Text("\(Int((score * 100).rounded()))")
                        .font(.system(size: size * 0.32, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("%")
                        .font(.system(size: size * 0.16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    let symbolName: String
    let value: String
    let caption: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)

            ZStack {
                if points.count > 1 {
                    // Fill under the curve.
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                    Circle()
                        .fill(tint)
                        .frame(width: 4.5, height: 4.5)
                        .position(points[points.count - 1])
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        // Fixed 0...1 domain so the shape is comparable between students.
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let clamped = min(1, max(0, value))
            return CGPoint(
                x: CGFloat(index) * stepX,
                y: size.height - (CGFloat(clamped) * size.height)
            )
        }
    }
}

// MARK: - Pressable row style

/// Row-shaped button with a hover highlight, used for every tappable list row.
struct RowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.rowCornerRadius
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill(isPressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return Theme.surfaceHover }
        return isHovering ? Theme.surface : Color.clear
    }
}

// MARK: - Toolbar icon button

struct ToolbarIconButton: View {
    let systemName: String
    var help: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Theme.surface : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(help)
    }
}

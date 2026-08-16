//
//  Theme.swift
//  Anchor
//
//  Shared metrics, colors and small view helpers. Colors are appearance-aware
//  so the popover reads correctly in both light and dark mode.
//

import SwiftUI

enum Theme {

    // MARK: - Metrics

    static let popoverWidth: CGFloat = 380
    static let popoverHeight: CGFloat = 500
    static let contentPadding: CGFloat = 14
    static let rowCornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 12

    // MARK: - Colors

    static let riskHigh = Color.dynamic(
        light: NSColor(srgbRed: 0.84, green: 0.19, blue: 0.19, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.42, blue: 0.40, alpha: 1)
    )

    static let riskElevated = Color.dynamic(
        light: NSColor(srgbRed: 0.79, green: 0.53, blue: 0.05, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.76, blue: 0.28, alpha: 1)
    )

    static let riskLow = Color.dynamic(
        light: NSColor(srgbRed: 0.14, green: 0.55, blue: 0.30, alpha: 1),
        dark: NSColor(srgbRed: 0.36, green: 0.83, blue: 0.53, alpha: 1)
    )

    static let accent = Color.dynamic(
        light: NSColor(srgbRed: 0.15, green: 0.39, blue: 0.85, alpha: 1),
        dark: NSColor(srgbRed: 0.44, green: 0.65, blue: 1.00, alpha: 1)
    )

    /// Row / card fill that sits on the popover's translucent background.
    static let surface = Color.dynamic(
        light: NSColor(white: 0.0, alpha: 0.045),
        dark: NSColor(white: 1.0, alpha: 0.065)
    )

    static let surfaceHover = Color.dynamic(
        light: NSColor(white: 0.0, alpha: 0.085),
        dark: NSColor(white: 1.0, alpha: 0.115)
    )

    static let hairline = Color.dynamic(
        light: NSColor(white: 0.0, alpha: 0.10),
        dark: NSColor(white: 1.0, alpha: 0.12)
    )

    // MARK: - Typography

    static let titleFont = Font.system(size: 13, weight: .semibold)
    static let rowNameFont = Font.system(size: 13, weight: .medium)
    static let scoreFont = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let captionFont = Font.system(size: 11)
    static let sectionFont = Font.system(size: 10, weight: .semibold)

    // MARK: - Formatting

    /// mm:ss, or h:mm:ss past an hour.
    static func elapsedString(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// "Just now", "3 min ago", "1 hr 12 min ago"
    static func relativeString(from date: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 45 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(1, minutes)) min ago" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr ago" : "\(hours) hr \(remainder) min ago"
    }

    /// "3 Sep" — compact enough for an assignment due date in a list row.
    static func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

extension Color {
    /// Builds a color that resolves per appearance, so a single constant works
    /// in light and dark mode without asset catalog entries.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

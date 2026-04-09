import SwiftUI

// MARK: - Design Tokens
//
// Central constants for the Gas Town panel design system.
// See DESIGN.md for the full specification.
//
// All Gas Town panels must use these tokens — no hardcoded colors, fonts, or spacing.

// MARK: - Colors

enum GasTownColors {
    /// Running agents, healthy systems.
    static let active = Color(red: 0x34 / 255.0, green: 0xD3 / 255.0, blue: 0x99 / 255.0)
    /// Needs operator attention, high context.
    static let attention = Color(red: 0xFB / 255.0, green: 0xBF / 255.0, blue: 0x24 / 255.0)
    /// Stuck agents, failed builds, critical.
    static let error = Color(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0)
    /// Not running, no work.
    static let idle = Color(red: 0x6B / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0)

    /// Section background (subtle elevation) for dark mode.
    static let sectionBackgroundDark = Color(nsColor: NSColor(white: 0.15, alpha: 1.0))
    /// Section background (subtle elevation) for light mode.
    static let sectionBackgroundLight = Color(nsColor: NSColor(white: 0.95, alpha: 1.0))

    /// Panel background for dark mode.
    static let panelBackgroundDark = Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
    /// Panel background for light mode.
    static let panelBackgroundLight = Color(nsColor: NSColor(white: 0.98, alpha: 1.0))

    /// Return the appropriate panel background for the current color scheme.
    static func panelBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? panelBackgroundDark : panelBackgroundLight
    }

    /// Return the appropriate section background for the current color scheme.
    static func sectionBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? sectionBackgroundDark : sectionBackgroundLight
    }
}

// MARK: - Spacing

enum GasTownSpacing {
    /// Internal padding of cards.
    static let cardPadding: CGFloat = 12
    /// Vertical gap between sections.
    static let sectionGap: CGFloat = 16
    /// Gap between grid items.
    static let gridGap: CGFloat = 8
    /// Horizontal padding in rows.
    static let rowPaddingH: CGFloat = 16
    /// Vertical padding in rows.
    static let rowPaddingV: CGFloat = 8
}

// MARK: - Typography

enum GasTownTypography {
    /// Section headers: system semibold 14pt.
    static let sectionHeader: Font = .system(size: 14, weight: .semibold)
    /// Labels: system regular 13pt.
    static let label: Font = .system(size: 13)
    /// Data / values: monospace 12pt.
    static let data: Font = .system(size: 12, design: .monospaced)
    /// Caption: system 11pt.
    static let caption: Font = .system(size: 11)
    /// Badge: system medium 10pt.
    static let badge: Font = .system(size: 10, weight: .medium)
}

// MARK: - Animation

enum GasTownAnimation {
    /// Cross-fade for status changes.
    static let statusChange: Animation = .easeInOut(duration: 0.2)
    /// Slide-in for new items.
    static let newItem: Animation = .easeOut(duration: 0.3)
    /// Fade-out for removed items.
    static let removeItem: Animation = .easeIn(duration: 0.2)

    /// Duration values for reference.
    static let statusChangeDuration: TimeInterval = 0.2
    static let newItemDuration: TimeInterval = 0.3
    static let removeItemDuration: TimeInterval = 0.2
}

// MARK: - Agent Role Icons

enum GasTownRoleIcon {
    /// Return the SF Symbol name for an agent role.
    static func sfSymbol(for role: String) -> String {
        switch role.lowercased() {
        case "mayor", "coordinator":
            return "crown"
        case "polecat", "worker":
            return "wrench"
        case "refinery":
            return "gearshape.2"
        case "witness":
            return "eye"
        case "crew":
            return "doc.on.clipboard"
        case "deacon":
            return "dog"
        default:
            return "person"
        }
    }
}

// MARK: - Status Dot

enum GasTownStatusDot {
    /// Standard status dot diameter.
    static let size: CGFloat = 8
}

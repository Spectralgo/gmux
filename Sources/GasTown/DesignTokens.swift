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
    /// Not running, no work (non-polecat roles only — polecats don't idle).
    static let idle = Color(red: 0x6B / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0)
    /// Polecat stalled: has work but session not running (needs intervention).
    static let stalled = Color(red: 0xFB / 255.0, green: 0xBF / 255.0, blue: 0x24 / 255.0)

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

// MARK: - Role Border Colors

enum GasTownRoleColors {
    static let worker = Color(red: 0.231, green: 0.510, blue: 0.965)        // #3B82F6 blue
    static let specialist = Color(red: 0.545, green: 0.361, blue: 0.965)    // #8B5CF6 purple
    static let infrastructure = Color(red: 0.063, green: 0.725, blue: 0.506) // #10B981 green
    static let coordinator = Color(red: 0.961, green: 0.620, blue: 0.043)   // #F59E0B gold
}

// MARK: - Role SF Symbol Icons

enum GasTownRoleIcons {
    static let mayor = "crown.fill"
    static let polecat = "wrench.fill"
    static let crew = "doc.on.clipboard"
    static let refinery = "building.2.fill"
    static let witness = "eye.fill"
    static let deacon = "dog.fill"
}

// MARK: - Agent Role Icons (legacy)

enum GasTownRoleIcon {
    /// Return the SF Symbol name for an agent role.
    static func sfSymbol(for role: String) -> String {
        switch role.lowercased() {
        case "mayor", "coordinator":
            return GasTownRoleIcons.mayor
        case "polecat", "worker":
            return GasTownRoleIcons.polecat
        case "refinery":
            return GasTownRoleIcons.refinery
        case "witness":
            return GasTownRoleIcons.witness
        case "crew":
            return GasTownRoleIcons.crew
        case "deacon", "watchdog":
            return GasTownRoleIcons.deacon
        default:
            return "person.fill"
        }
    }
}

// MARK: - Role Group Ordering

enum AgentRoleGroup: Int, CaseIterable {
    case coordination = 0   // mayor
    case workers = 1        // polecats
    case specialists = 2    // crew
    case infrastructure = 3 // refinery, witness, deacon

    var title: String {
        switch self {
        case .coordination:
            return String(localized: "roleGroup.coordination", defaultValue: "Coordination")
        case .workers:
            return String(localized: "roleGroup.workers", defaultValue: "Workers")
        case .specialists:
            return String(localized: "roleGroup.specialists", defaultValue: "Specialists")
        case .infrastructure:
            return String(localized: "roleGroup.infrastructure", defaultValue: "Infrastructure")
        }
    }

    var borderColor: Color {
        switch self {
        case .coordination: return GasTownRoleColors.coordinator
        case .workers: return GasTownRoleColors.worker
        case .specialists: return GasTownRoleColors.specialist
        case .infrastructure: return GasTownRoleColors.infrastructure
        }
    }

    static func from(role: String) -> AgentRoleGroup {
        switch role.lowercased() {
        case "mayor", "coordinator": return .coordination
        case "polecat": return .workers
        case "crew": return .specialists
        case "refinery", "witness", "deacon", "watchdog": return .infrastructure
        default: return .workers
        }
    }

    static func icon(for role: String) -> String {
        GasTownRoleIcon.sfSymbol(for: role)
    }
}

// MARK: - Status Dot

enum GasTownStatusDot {
    /// Standard status dot diameter.
    static let size: CGFloat = 8
}

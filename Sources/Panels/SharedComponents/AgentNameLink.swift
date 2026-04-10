import SwiftUI

extension Notification.Name {
    static let openAgentProfile = Notification.Name("com.cmux.openAgentProfile")
    static let openConvoyBoard = Notification.Name("com.cmux.openConvoyBoard")
    static let createRigWorkspace = Notification.Name("com.cmux.createRigWorkspace")
    static let openRefineryPanel = Notification.Name("com.cmux.openRefineryPanel")
    static let openMailPanel = Notification.Name("com.cmux.openMailPanel")
}

/// Clickable agent name that navigates to Agent Profile.
///
/// Posts ``Notification.Name/openAgentProfile`` with the agent address in
/// `userInfo["agentAddress"]`. Reusable across all panels (Town Dashboard,
/// Rig Panel, Agent Health, etc.).
///
/// **Design spec:**
/// - Font: ``GasTownTypography/label`` (13pt)
/// - Clickable, posts `.openAgentProfile` notification on tap
struct AgentNameLink: View {
    let name: String
    let agentAddress: String

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .openAgentProfile,
                object: nil,
                userInfo: ["agentAddress": agentAddress]
            )
        } label: {
            Text(name)
                .font(GasTownTypography.label)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

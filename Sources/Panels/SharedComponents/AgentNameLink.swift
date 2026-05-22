import SwiftUI

extension Notification.Name {
    static let openAgentProfile = Notification.Name("com.cmux.openAgentProfile")
    static let openConvoyBoard = Notification.Name("com.cmux.openConvoyBoard")
    static let createRigWorkspace = Notification.Name("com.cmux.createRigWorkspace")
    static let openRefineryPanel = Notification.Name("com.cmux.openRefineryPanel")
    static let openMailPanel = Notification.Name("com.cmux.openMailPanel")
    static let openDiffPanel = Notification.Name("com.cmux.openDiffPanel")
    static let openTerminalAttach = Notification.Name("com.cmux.openTerminalAttach")
    static let openDiagnosticsPanel = Notification.Name("com.cmux.openDiagnosticsPanel")
}

enum PanelLinkUserInfo {
    static func agentProfile(agentAddress: String, workspaceId: UUID? = nil) -> [AnyHashable: Any] {
        userInfo(["agentAddress": agentAddress], workspaceId: workspaceId)
    }

    static func beadInspector(beadId: String, workspaceId: UUID? = nil) -> [AnyHashable: Any] {
        userInfo(["beadId": beadId], workspaceId: workspaceId)
    }

    static func diffPanel(commitSha: String, workspaceId: UUID? = nil) -> [AnyHashable: Any] {
        userInfo(["commitSha": commitSha], workspaceId: workspaceId)
    }

    static func terminalAttach(sessionName: String, workspaceId: UUID? = nil) -> [AnyHashable: Any] {
        userInfo(["sessionName": sessionName], workspaceId: workspaceId)
    }

    static func diagnosticsPanel(workspaceId: UUID? = nil) -> [AnyHashable: Any] {
        userInfo([:], workspaceId: workspaceId)
    }

    static func refineryPanel(rigId: String? = nil, itemId: String? = nil, workspaceId: UUID? = nil) -> [AnyHashable: Any] {
        var values: [String: Any] = [:]
        if let rigId {
            values["rigId"] = rigId
        }
        if let itemId {
            values["itemId"] = itemId
        }
        return userInfo(values, workspaceId: workspaceId)
    }

    private static func userInfo(_ values: [String: Any], workspaceId: UUID?) -> [AnyHashable: Any] {
        var userInfo = Dictionary(uniqueKeysWithValues: values.map { (AnyHashable($0.key), $0.value) })
        if let workspaceId {
            userInfo["workspaceId"] = workspaceId
        }
        return userInfo
    }
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
    var workspaceId: UUID? = nil

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .openAgentProfile,
                object: nil,
                userInfo: PanelLinkUserInfo.agentProfile(
                    agentAddress: agentAddress,
                    workspaceId: workspaceId
                )
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

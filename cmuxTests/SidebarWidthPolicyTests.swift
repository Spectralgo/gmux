import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class SidebarWidthPolicyTests: XCTestCase {
    func testContentViewClampAllowsNarrowSidebarBelowLegacyMinimum() {
        XCTAssertEqual(
            ContentView.clampedSidebarWidth(184, maximumWidth: 600),
            184,
            accuracy: 0.001
        )
    }
}

final class PanelLinkUserInfoTests: XCTestCase {
    func testAgentProfileLinkIncludesWorkspaceWhenProvided() {
        let workspaceId = UUID()

        let userInfo = PanelLinkUserInfo.agentProfile(
            agentAddress: "gmux/polecats/chrome",
            workspaceId: workspaceId
        )

        XCTAssertEqual(userInfo["agentAddress" as AnyHashable] as? String, "gmux/polecats/chrome")
        XCTAssertEqual(userInfo["workspaceId" as AnyHashable] as? UUID, workspaceId)
    }

    func testBeadInspectorLinkIncludesWorkspaceWhenProvided() {
        let workspaceId = UUID()

        let userInfo = PanelLinkUserInfo.beadInspector(
            beadId: "gm-ebc",
            workspaceId: workspaceId
        )

        XCTAssertEqual(userInfo["beadId" as AnyHashable] as? String, "gm-ebc")
        XCTAssertEqual(userInfo["workspaceId" as AnyHashable] as? UUID, workspaceId)
    }
}

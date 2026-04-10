import SwiftUI

/// Sticky bottom bar with contextual agent actions.
///
/// Actions vary by role:
/// - All roles: Attach, Send Mail, Nudge
/// - Mayor: Handoff
/// - Polecat: Nuke (destructive)
/// - Crew: Assign Work
struct ActionsBarView: View {
    let agentAddress: String
    let role: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: GasTownSpacing.gridGap) {
            // Attach — open terminal
            actionButton(
                label: String(localized: "agentProfile.action.attach", defaultValue: "Attach"),
                icon: "terminal",
                action: attachAction
            )

            // Send Mail
            actionButton(
                label: String(localized: "agentProfile.action.sendMail", defaultValue: "Mail"),
                icon: "envelope",
                action: sendMailAction
            )

            // Nudge
            actionButton(
                label: String(localized: "agentProfile.action.nudge", defaultValue: "Nudge"),
                icon: "hand.wave",
                action: nudgeAction
            )

            Spacer()

            // Role-specific actions
            if isMayor {
                actionButton(
                    label: String(localized: "agentProfile.action.handoff", defaultValue: "Handoff"),
                    icon: "arrow.right.arrow.left",
                    action: handoffAction
                )
            }

            if isCrew {
                actionButton(
                    label: String(localized: "agentProfile.action.assign", defaultValue: "Assign"),
                    icon: "tray.and.arrow.down",
                    action: assignAction
                )
            }

            if isPolecat {
                Button {
                    nukeAction()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "flame")
                            .font(.system(size: 12))
                        Text(String(localized: "agentProfile.action.nuke", defaultValue: "Nuke"))
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(GasTownColors.error)
            }
        }
        .padding(.horizontal, GasTownSpacing.rowPaddingH)
        .padding(.vertical, 12)
        .background(GasTownColors.sectionBackground(for: colorScheme))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func actionButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var isMayor: Bool {
        role?.lowercased() == "mayor" || role?.lowercased() == "coordinator"
    }

    private var isPolecat: Bool {
        role?.lowercased() == "polecat" || role?.lowercased() == "worker"
    }

    private var isCrew: Bool {
        role?.lowercased() == "crew"
    }

    // MARK: - Actions

    private func attachAction() {
        runGTCommand(["attach", agentAddress])
    }

    private func sendMailAction() {
        runGTCommand(["mail", "send", agentAddress, "-s", "Message from profile", "-m", ""])
    }

    private func nudgeAction() {
        runGTCommand(["nudge", agentAddress, "Check in from profile"])
    }

    private func handoffAction() {
        runGTCommand(["handoff", "-s", "Handoff from profile"])
    }

    private func assignAction() {
        runGTCommand(["sling", "ready", agentAddress])
    }

    private func nukeAction() {
        runGTCommand(["nuke", agentAddress])
    }

    private func runGTCommand(_ arguments: [String]) {
        guard let gtPath = GasTownCLIRunner.resolveGTCLI() else { return }
        let townPath = GasTownService.shared.townRoot?.path

        DispatchQueue.global(qos: .userInitiated).async {
            let _ = GasTownCLIRunner.runProcess(
                executablePath: gtPath,
                arguments: arguments,
                townRootPath: townPath
            )
        }
    }
}

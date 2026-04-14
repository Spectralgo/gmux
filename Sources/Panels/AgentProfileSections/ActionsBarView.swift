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

    // MARK: - Actions (via socket handlers)

    private func attachAction() {
        Task {
            _ = await GastownSocketHandlers.gastownAgentAttach(params: ["address": agentAddress])
        }
    }

    private func sendMailAction() {
        Task {
            _ = await GastownSocketHandlers.gastownMailSend(params: [
                "address": agentAddress,
                "subject": "Message from profile",
                "body": "",
            ])
        }
    }

    private func nudgeAction() {
        Task {
            _ = await GastownSocketHandlers.gastownAgentNudge(params: [
                "address": agentAddress,
                "message": "Check in from profile",
            ])
        }
    }

    private func handoffAction() {
        Task {
            _ = await GastownSocketHandlers.gastownAgentHandoff(params: [
                "subject": "Handoff from profile",
            ])
        }
    }

    private func assignAction() {
        Task {
            _ = await GastownSocketHandlers.gastownAgentSling(params: ["address": agentAddress])
        }
    }

    private func nukeAction() {
        Task {
            _ = await GastownSocketHandlers.gastownAgentNuke(params: ["address": agentAddress])
        }
    }
}

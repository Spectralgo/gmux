import SwiftUI

/// Section displaying agent memories with add/delete support.
struct MemorySection: View {
    let memories: [String]
    let onAddMemory: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isAddingMemory = false
    @State private var newMemoryText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: GasTownSpacing.gridGap) {
            HStack {
                Text(String(localized: "agentProfile.memory.title", defaultValue: "Memories"))
                    .font(GasTownTypography.sectionHeader)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(String(
                    localized: "agentProfile.memory.count",
                    defaultValue: "\(memories.count)"
                ))
                .font(GasTownTypography.caption)
                .foregroundColor(.secondary)
            }

            if memories.isEmpty && !isAddingMemory {
                Text(String(localized: "agentProfile.memory.empty", defaultValue: "No memories stored"))
                    .font(GasTownTypography.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(memories.enumerated()), id: \.offset) { _, memory in
                    memoryRow(memory)
                }
            }

            if isAddingMemory {
                HStack(spacing: 4) {
                    TextField(
                        String(localized: "agentProfile.memory.placeholder", defaultValue: "New memory..."),
                        text: $newMemoryText
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(GasTownTypography.label)
                    .onSubmit { commitMemory() }

                    Button {
                        commitMemory()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newMemoryText.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button {
                        isAddingMemory = false
                        newMemoryText = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Button {
                    isAddingMemory = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text(String(localized: "agentProfile.memory.add", defaultValue: "Add Memory"))
                            .font(GasTownTypography.caption)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(GasTownSpacing.cardPadding)
        .background(GasTownColors.sectionBackground(for: colorScheme))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "agentProfile.memory.section.a11y",
            defaultValue: "Memories section"
        ))
    }

    @ViewBuilder
    private func memoryRow(_ memory: String) -> some View {
        HStack(alignment: .top, spacing: GasTownSpacing.gridGap) {
            Image(systemName: "brain")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)

            Text(memory)
                .font(GasTownTypography.label)
                .lineLimit(3)

            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "agentProfile.memory.row.a11y",
            defaultValue: "Memory: \(memory)"
        ))
    }

    private func commitMemory() {
        let trimmed = newMemoryText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAddMemory(trimmed)
        newMemoryText = ""
        isAddingMemory = false
    }
}

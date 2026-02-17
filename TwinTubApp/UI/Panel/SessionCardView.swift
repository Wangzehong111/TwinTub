import SwiftUI

struct SessionCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: SessionModel
    let onJumpAuto: () -> TerminalJumpService.JumpOutcome
    let onJumpManual: (TerminalJumpService.JumpTarget) -> Bool

    @State private var pulse = false
    @State private var showJumpPicker = false
    @State private var manualTargets: [TerminalJumpService.JumpTarget] = []
    @State private var jumpReason = "Choose a jump target."

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(statusColor)
                .frame(width: 5, height: 52)
                .scaleEffect(session.status == .processing && pulse ? 1.02 : 1.0)
                .opacity(session.status == .waiting && pulse ? 0.55 : 1.0)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.projectName)
                    .font(ThemeTokens.mono(size: 14, weight: .bold))
                    .foregroundStyle(ThemeTokens.text(for: colorScheme))
                    .lineLimit(1)

                Text(session.displayStatusLine)
                    .font(ThemeTokens.mono(size: 10))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CONTEXT_WINDOW_USAGE")
                        .font(ThemeTokens.mono(size: 8))
                        .foregroundStyle(ThemeTokens.textDim(for: colorScheme))
                    SegmentedUsageBarView(filled: session.usageSegments)
                }

                if let sourceLine = session.sourceDisplayLine {
                    Text(sourceLine)
                        .font(ThemeTokens.mono(size: 9))
                        .foregroundStyle(ThemeTokens.textDim(for: colorScheme))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: handleJump) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(ThemeTokens.textDim(for: colorScheme))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ThemeTokens.border(for: colorScheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Jump")
            .accessibilityLabel("Jump to terminal session")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ThemeTokens.border(for: colorScheme), lineWidth: 1)
        )
        .animation(
            shouldAnimatePulse
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                : .default,
            value: pulse
        )
        .onAppear {
            if shouldAnimatePulse {
                pulse = true
            }
        }
        .confirmationDialog("SELECT JUMP TARGET", isPresented: $showJumpPicker, titleVisibility: .visible) {
            ForEach(manualTargets) { target in
                Button(target.displayName) {
                    _ = onJumpManual(target)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(jumpReason)
        }
    }

    private func handleJump() {
        switch onJumpAuto() {
        case .success:
            return
        case let .needsManualSelection(targets, reason):
            manualTargets = targets
            jumpReason = reason
            showJumpPicker = true
        }
    }

    private var shouldAnimatePulse: Bool {
        session.status == .processing || session.status == .waiting
    }

    private var statusColor: Color {
        switch session.status {
        case .waiting:
            return ThemeTokens.pink(for: colorScheme)
        case .processing:
            return ThemeTokens.amber(for: colorScheme)
        case .completed:
            return ThemeTokens.green(for: colorScheme)
        case .destroyed:
            return ThemeTokens.textDim(for: colorScheme)
        }
    }
}

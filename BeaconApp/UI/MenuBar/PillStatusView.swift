import SwiftUI

struct PillStatusView: View {
    @Environment(\.colorScheme) private var colorScheme

    let status: SessionStore.GlobalStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            Text(label)
                .font(ThemeTokens.mono(size: 10, weight: .semibold))
                .foregroundStyle(ThemeTokens.text(for: colorScheme))

            if case let .waiting(count) = status {
                Text("x\(count)")
                    .font(ThemeTokens.mono(size: 10, weight: .bold))
                    .foregroundStyle(ThemeTokens.pink(for: colorScheme))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35))
        )
        .overlay(
            Capsule().stroke(ThemeTokens.border(for: colorScheme), lineWidth: 1)
        )
        .frame(height: 22)
    }

    private var label: String {
        switch status {
        case .idle: return "IDLE"
        case .processing: return "PROCESSING"
        case .waiting: return "WAITING"
        case .done: return "DONE"
        }
    }

    private var dotColor: Color {
        switch status {
        case .idle:
            return ThemeTokens.textDim(for: colorScheme)
        case .processing:
            return ThemeTokens.amber(for: colorScheme)
        case .waiting:
            return ThemeTokens.pink(for: colorScheme)
        case .done:
            return ThemeTokens.green(for: colorScheme)
        }
    }
}

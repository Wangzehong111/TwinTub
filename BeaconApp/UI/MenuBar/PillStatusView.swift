import SwiftUI

struct PillStatusView: View {
    let status: SessionStore.GlobalStatus

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .frame(width: 20, height: 16)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        switch status {
        case .idle:
            return "Beacon Idle"
        case .processing:
            return "Beacon Processing"
        case .waiting:
            return "Beacon Waiting for Input"
        case .done:
            return "Beacon Done"
        }
    }

    private var symbolName: String {
        switch status {
        case .idle:
            return "circle"
        case .processing:
            return "hourglass.circle"
        case .waiting:
            return "exclamationmark.triangle"
        case .done:
            return "checkmark.circle"
        }
    }
}

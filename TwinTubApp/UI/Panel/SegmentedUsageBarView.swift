import SwiftUI

struct SegmentedUsageBarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let filled: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...TwinTubConfig.usageBarSegments, id: \.self) { index in
                Rectangle()
                    .fill(fillColor(for: index))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 10)
    }

    private func fillColor(for index: Int) -> Color {
        guard index <= filled else {
            return ThemeTokens.highlight(for: colorScheme)
        }
        // Calculate thresholds based on total segments
        let totalSegments = TwinTubConfig.usageBarSegments
        let amberThreshold = totalSegments / 2  // 50%
        let pinkThreshold = Int(Double(totalSegments) * 0.8)  // 80%

        if index <= amberThreshold {
            return ThemeTokens.textDim(for: colorScheme).opacity(0.8)
        }
        if index <= pinkThreshold {
            return ThemeTokens.amber(for: colorScheme)
        }
        return ThemeTokens.pink(for: colorScheme)
    }
}

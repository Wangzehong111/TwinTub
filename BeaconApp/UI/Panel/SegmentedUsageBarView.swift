import SwiftUI

struct SegmentedUsageBarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let filled: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...10, id: \.self) { index in
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
        if index <= 5 {
            return ThemeTokens.textDim(for: colorScheme).opacity(0.8)
        }
        if index <= 8 {
            return ThemeTokens.amber(for: colorScheme)
        }
        return ThemeTokens.pink(for: colorScheme)
    }
}

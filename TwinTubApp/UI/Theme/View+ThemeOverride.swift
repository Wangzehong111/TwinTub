import SwiftUI
import AppKit

extension View {
    @ViewBuilder
    func twinTubThemeOverride(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            self.environment(\.colorScheme, scheme)
        } else {
            self.environment(\.colorScheme, resolveSystemColorScheme())
        }
    }
}

@MainActor
private func resolveSystemColorScheme() -> ColorScheme {
    let appearance = NSApp?.effectiveAppearance
    let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return isDark ? .dark : .light
}

import SwiftUI

enum ThemePreference: String, CaseIterable {
    case system
    case dark
    case light

    var overrideColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    mutating func toggleDarkLight() {
        switch self {
        case .system:
            self = .dark
        case .dark:
            self = .light
        case .light:
            self = .dark
        }
    }
}

enum ThemeTokens {
    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#050607") : Color(hex: "#F7F3E0")
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    static func text(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#E8DCC8") : Color(hex: "#2B2520")
    }

    static func textDim(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.55)
    }

    static func amber(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#FFB347") : Color(hex: "#D97706")
    }

    static func pink(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#FF6B6B") : Color(hex: "#D04A66")
    }

    static func green(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#7CFC00") : Color(hex: "#059669")
    }

    static func highlight(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 6:
            (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

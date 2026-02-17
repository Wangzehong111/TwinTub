import SwiftUI

struct TwinTubPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SessionStore
    let jumpService: TerminalJumpService
    let themePreference: ThemePreference
    let onToggleTheme: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            controls
            Divider().overlay(ThemeTokens.border(for: colorScheme))

            if store.sessions.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.sessions) { session in
                            SessionCardView(
                                session: session,
                                onJumpAuto: { jumpService.jump(to: session) },
                                onJumpManual: { target in
                                    jumpService.jump(session: session, forcedTarget: target)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            Text("--- END OF TRANSMISSION ---")
                .font(ThemeTokens.mono(size: 9, weight: .bold))
                .foregroundStyle(ThemeTokens.highlight(for: colorScheme))
        }
        .padding(16)
        .frame(width: 320)
        .background(ThemeTokens.background(for: colorScheme).opacity(colorScheme == .dark ? 0.86 : 0.94))
    }

    private var header: some View {
        HStack {
            Text("TWINTUB_SYSTEM_v1.0")
                .font(ThemeTokens.mono(size: 12, weight: .bold))
                .foregroundStyle(ThemeTokens.amber(for: colorScheme))
            Spacer()
            Text("[ ACTIVE_SESSIONS: \(store.sessions.count) ]")
                .font(ThemeTokens.mono(size: 10))
                .foregroundStyle(ThemeTokens.textDim(for: colorScheme))
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Spacer()

            Button(action: onToggleTheme) {
                Image(systemName: themePreference == .light ? "moon.stars.fill" : "sun.max.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textDim(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ThemeTokens.border(for: colorScheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle Dark/Light Theme")
            .accessibilityLabel("Toggle Dark or Light Theme")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ThemeTokens.highlight(for: colorScheme))
            Text("STANDBY_MODE")
                .font(ThemeTokens.mono(size: 13, weight: .bold))
                .foregroundStyle(ThemeTokens.highlight(for: colorScheme))
            Text("Waiting for agent initialization...")
                .font(ThemeTokens.mono(size: 10))
                .foregroundStyle(ThemeTokens.highlight(for: colorScheme))
            Button("OPEN LAST ACTIVE SESSION") {
                if let session = store.lastActiveSession {
                    _ = jumpService.jump(to: session)
                }
            }
            .font(ThemeTokens.mono(size: 10, weight: .semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

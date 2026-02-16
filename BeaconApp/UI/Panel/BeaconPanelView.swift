import SwiftUI

struct BeaconPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SessionStore
    let jumpService: TerminalJumpService

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider().overlay(ThemeTokens.border(for: colorScheme))

            if store.sessions.isEmpty {
                emptyView
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.sessions) { session in
                            SessionCardView(session: session) {
                                _ = jumpService.jump(to: session)
                            }
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
            Text("BEACON_SYSTEM_v1.0")
                .font(ThemeTokens.mono(size: 12, weight: .bold))
                .foregroundStyle(ThemeTokens.amber(for: colorScheme))
            Spacer()
            Text("[ ACTIVE_SESSIONS: \(store.sessions.count) ]")
                .font(ThemeTokens.mono(size: 10))
                .foregroundStyle(ThemeTokens.textDim(for: colorScheme))
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

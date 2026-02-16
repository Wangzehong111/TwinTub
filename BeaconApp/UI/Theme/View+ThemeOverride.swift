import SwiftUI

extension View {
    @ViewBuilder
    func beaconThemeOverride(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            self.environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}

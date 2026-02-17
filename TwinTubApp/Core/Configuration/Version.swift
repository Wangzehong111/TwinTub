import Foundation

/// TwinTub version information
///
/// Default version values used for development builds.
/// Release builds should update these values from git tags.
public enum TwinTubVersion {
    /// Version string (e.g., "1.0.0")
    /// Update this before each release or use build scripts to automate.
    public static let current = "1.0.0"

    /// Build number (increment for each build)
    /// Update this before each release or use build scripts to automate.
    public static let build = 1

    /// Full version string with build number
    public static var full: String {
        "\(current) (\(build))"
    }
}

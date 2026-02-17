import Foundation

/// TwinTub version information
///
/// This file is auto-generated during the build process.
/// Do not edit manually - version is derived from git tags.
public enum TwinTubVersion {
    /// Version string (e.g., "1.0.0")
    public static let current = "1.0.0"

    /// Build number (commit count)
    public static let build = 1

    /// Full version string with build number
    public static var full: String {
        "\(current) (\(build))"
    }
}

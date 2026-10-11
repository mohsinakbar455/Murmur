import Foundation

/// Centralized branding configuration for Murmur.
///
/// Ensures consistent naming across window titles, menus, headers, about screens,
/// and sidebar footers without scattering hard-coded strings.
public enum Branding {
    /// Public display name of the application.
    public static let appName = "Murmur"

    /// Attribution shown in sidebar footer and About screen.
    public static let byline = "Murmur by Mohsin"

    /// Author attribution for about dialogs and metadata.
    public static let author = "Mohsin"

    /// Version string for display.
    public static let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"

    /// Bundle identifier of the current Murmur app.
    public static let bundleIdentifier = "ai.pivotstudio.murmur"

    /// URL scheme for internal deep links.
    public static let urlScheme = "murmur"
}

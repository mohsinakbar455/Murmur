import OSLog

enum Log {
    static let audio = Logger(subsystem: Branding.bundleIdentifier, category: "audio")
    static let speech = Logger(subsystem: Branding.bundleIdentifier, category: "speech")
    static let hotkey = Logger(subsystem: Branding.bundleIdentifier, category: "hotkey")
    static let inject = Logger(subsystem: Branding.bundleIdentifier, category: "inject")
    static let app = Logger(subsystem: Branding.bundleIdentifier, category: "app")
}

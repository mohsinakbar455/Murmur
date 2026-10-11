import AppKit
import UniformTypeIdentifiers

struct PersonalizationApplication: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL?
}

/// Familiar app names in the UI; bundle identifiers are only persistence keys.
@MainActor
enum PersonalizationApplications {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return "Selected app"
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    static func available(including saved: [WritingAppRule] = []) -> [PersonalizationApplication] {
        var values: [String: PersonalizationApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != Branding.bundleIdentifier else { continue }
            values[id] = PersonalizationApplication(bundleID: id, name: app.localizedName ?? name(for: id), url: app.bundleURL)
        }
        for rule in saved where values[rule.bundleID] == nil {
            values[rule.bundleID] = PersonalizationApplication(bundleID: rule.bundleID, name: rule.appName,
                url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID))
        }
        return values.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func choose() -> PersonalizationApplication? {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.prompt = "Choose App"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        return PersonalizationApplication(bundleID: id,
            name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url: url)
    }
}

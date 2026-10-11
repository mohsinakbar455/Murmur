import Foundation

/// Murmur's single home for application data.
enum MurmurStorage {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur", isDirectory: true)
    }

    /// Copy previous app data before any store or model manager opens its files.
    /// The source remains available for rollback until the new app is verified.
    static func prepareForLaunch() {
        let previous = directory.deletingLastPathComponent()
            .appendingPathComponent("MurmurYouTube", isDirectory: true)
        do {
            try copyPreviousData(from: previous, to: directory)
        } catch {
            NSLog("Murmur data migration could not finish: %@", error.localizedDescription)
        }
        copyPreviousPreferences()
    }

    static func copyPreviousData(from previous: URL, to current: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: previous.path) else { return }

        for source in try fileManager.contentsOfDirectory(at: previous, includingPropertiesForKeys: nil)
        where source.lastPathComponent != ".DS_Store" {
            let destination = current.appendingPathComponent(source.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }

            let temporary = current.appendingPathComponent(".migrating-\(UUID().uuidString)")
            do {
                try fileManager.copyItem(at: source, to: temporary)
                guard copiesMatch(source, temporary, fileManager: fileManager) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try fileManager.moveItem(at: temporary, to: destination)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        }
    }

    private static func copiesMatch(_ source: URL, _ copy: URL, fileManager: FileManager) -> Bool {
        guard let sourceType = try? fileManager.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType,
              let copyType = try? fileManager.attributesOfItem(atPath: copy.path)[.type] as? FileAttributeType,
              sourceType == copyType else { return false }
        if sourceType == .typeDirectory {
            guard let children = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil),
                  let copied = try? fileManager.contentsOfDirectory(at: copy, includingPropertiesForKeys: nil),
                  Set(children.map(\.lastPathComponent)) == Set(copied.map(\.lastPathComponent)) else { return false }
            return children.allSatisfy {
                copiesMatch($0, copy.appendingPathComponent($0.lastPathComponent), fileManager: fileManager)
            }
        }
        return fileManager.contentsEqual(atPath: source.path, andPath: copy.path)
    }

    static func copyPreviousPreferences(
        defaults: UserDefaults = .standard,
        previousDomain: String = "ai.pivotstudio.murmur-youtube",
        currentDomain: String = Branding.bundleIdentifier
    ) {
        guard let previous = defaults.persistentDomain(forName: previousDomain), !previous.isEmpty else { return }
        var current = defaults.persistentDomain(forName: currentDomain) ?? [:]
        for (key, value) in previous where current[key] == nil {
            current[key] = value
        }
        defaults.setPersistentDomain(current, forName: currentDomain)
    }
}

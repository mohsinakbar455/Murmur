import Foundation
import Observation

@MainActor
@Observable
final class MeetingStore {
    private(set) var meetings: [MeetingRecord] = []
    private(set) var loadWarnings: [String] = []
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? MurmurStorage.directory
            .appendingPathComponent("Meetings", isDirectory: true)
        load()
    }

    func meeting(_ id: UUID) -> MeetingRecord? { meetings.first { $0.id == id } }

    func save(_ meeting: MeetingRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let destination = directory.appendingPathComponent(meeting.id.uuidString).appendingPathExtension("json")
        try encoder.encode(meeting).write(to: destination, options: .atomic)
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) { meetings[index] = meeting }
        else { meetings.append(meeting) }
        meetings.sort { $0.startedAt > $1.startedAt }
    }

    func update(_ id: UUID, _ mutation: (inout MeetingRecord) -> Void) throws {
        guard var record = meeting(id) else { return }
        mutation(&record)
        try save(record)
    }

    func delete(_ id: UUID) throws {
        let file = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        meetings.removeAll { $0.id == id }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                do {
                    var record = try JSONDecoder().decode(MeetingRecord.self, from: Data(contentsOf: file))
                    if record.endedAt == nil {
                        record.interrupted = true
                        record.endedAt = record.startedAt.addingTimeInterval(record.segments.map(\.end).max() ?? 0)
                        // Recover only after decoding succeeded; never overwrite unreadable documents.
                        try save(record)
                    } else { meetings.append(record) }
                } catch {
                    loadWarnings.append("Could not open \(file.lastPathComponent): \(error.localizedDescription). The original file has been kept.")
                }
            }
            meetings.sort { $0.startedAt > $1.startedAt }
        } catch { loadWarnings.append("Meetings could not be loaded: \(error.localizedDescription)") }
    }
}

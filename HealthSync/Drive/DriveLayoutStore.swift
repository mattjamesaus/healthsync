import Foundation

struct DriveLayout: Codable, Equatable, Sendable {
    var accountEmail: String
    var rootFolderId: String
    var folders: [String: String]
    var files: [String: String]
}

final class DriveLayoutStore: @unchecked Sendable {
    static let shared = DriveLayoutStore()

    private let url: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("DriveLayout.json")
    }

    func load() -> DriveLayout? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DriveLayout.self, from: data)
    }

    func save(_ layout: DriveLayout) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? encoder.encode(layout) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }
}

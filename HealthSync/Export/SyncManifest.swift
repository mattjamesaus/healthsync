import Foundation

struct SyncManifest: Codable, Sendable {
    let syncedAt: String
    let windowStart: String
    let windowEnd: String
    let watermarkAfter: String
    let sampleRowsWritten: Int
    let workoutRowsWritten: Int
    let metrics: [String]
    let destination: String
    let notes: String?
}

enum SyncManifestWriter {
    static func write(
        _ manifest: SyncManifest,
        to directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let stamp = manifest.syncedAt
            .replacingOccurrences(of: ":", with: "")
        let fileURL = directory.appendingPathComponent("sync_\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

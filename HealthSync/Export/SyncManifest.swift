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
    static func encode(_ manifest: SyncManifest) throws -> (fileName: String, data: Data) {
        let stamp = manifest.syncedAt
            .replacingOccurrences(of: ":", with: "")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        return ("sync_\(stamp).json", data)
    }
}

import Foundation

protocol SyncDestination: Sendable {
    var displayName: String { get }
    func read(relativePath: String) async throws -> Data?
    func write(relativePath: String, data: Data, mimeType: String) async throws
}

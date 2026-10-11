import Foundation

enum BookmarkStoreError: LocalizedError {
    case noDestination
    case staleBookmark
    case cannotAccess
    case bookmarkCreationFailed

    var errorDescription: String? {
        switch self {
        case .noDestination:
            return "Choose a save folder before syncing."
        case .staleBookmark:
            return "The saved folder is no longer available. Pick it again."
        case .cannotAccess:
            return "Could not access the saved folder."
        case .bookmarkCreationFailed:
            return "Could not remember the selected folder."
        }
    }
}

@MainActor
final class BookmarkStore: ObservableObject {
    private let bookmarkKey = "destinationBookmark"
    private let displayNameKey = "destinationDisplayName"

    @Published private(set) var displayName: String?
    @Published private(set) var hasDestination: Bool = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        hasDestination = defaults.data(forKey: bookmarkKey) != nil
        displayName = defaults.string(forKey: displayNameKey)
    }

    func save(folderURL: URL) throws {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        // iOS/iPadOS: empty options + startAccessingSecurityScopedResource for Files picks.
        let data = try folderURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(folderURL.lastPathComponent, forKey: displayNameKey)
        reload()
    }

    func clear() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: displayNameKey)
        reload()
    }

    /// Resolves the bookmarked folder and starts security-scoped access.
    /// Caller must call `stopAccessing` when finished.
    func resolveAccessibleURL() throws -> (url: URL, stopAccessing: () -> Void) {
        guard let data = defaults.data(forKey: bookmarkKey) else {
            throw BookmarkStoreError.noDestination
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            // Refresh bookmark if possible.
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let refreshed = try? url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    defaults.set(refreshed, forKey: bookmarkKey)
                }
            } else {
                throw BookmarkStoreError.staleBookmark
            }
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkStoreError.cannotAccess
        }

        return (url, { url.stopAccessingSecurityScopedResource() })
    }
}

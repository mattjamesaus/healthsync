import Foundation

actor DriveDestination: SyncDestination {
    nonisolated let displayName: String

    private let client: DriveClient
    private let layoutStore: DriveLayoutStore
    private let tokenProvider: @Sendable () async throws -> String
    private let accountEmail: String
    private var layout: DriveLayout?

    init(
        accountEmail: String,
        client: DriveClient = DriveClient(),
        layoutStore: DriveLayoutStore = .shared,
        tokenProvider: @escaping @Sendable () async throws -> String = { try await GoogleAuth.accessToken() }
    ) {
        self.displayName = "Google Drive"
        self.accountEmail = accountEmail
        self.client = client
        self.layoutStore = layoutStore
        self.tokenProvider = tokenProvider
        if let existing = layoutStore.load(), existing.accountEmail == accountEmail {
            self.layout = existing
        } else {
            self.layout = nil
        }
    }

    func read(relativePath: String) async throws -> Data? {
        try await ensureLayout()
        guard let fileID = layout?.files[relativePath] else {
            return nil
        }

        do {
            if let data = try await withAuthorizedToken({ token in
                try await self.client.download(fileID: fileID, accessToken: token)
            }) {
                return data
            }
            removeFileID(for: relativePath)
            return nil
        } catch DriveClientError.httpStatus(404, _) {
            removeFileID(for: relativePath)
            return nil
        }
    }

    func write(relativePath: String, data: Data, mimeType: String) async throws {
        try await ensureLayout()
        let parts = relativePath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw DriveClientError.invalidURL
        }
        let folderName = String(parts[0])
        let fileName = String(parts[1])
        let parentID = try folderID(named: folderName)

        if mimeType == "application/json" || folderName == "manifests" {
            _ = try await withAuthorizedToken { token in
                try await self.client.createJSON(
                    name: fileName,
                    parentID: parentID,
                    data: data,
                    accessToken: token
                )
            }
            return
        }

        if let fileID = layout?.files[relativePath] {
            do {
                try await withAuthorizedToken { token in
                    try await self.client.updateCSV(
                        fileID: fileID,
                        data: data,
                        accessToken: token
                    )
                }
                return
            } catch DriveClientError.httpStatus(404, _) {
                removeFileID(for: relativePath)
            }
        }

        let createdID = try await withAuthorizedToken { token in
            try await self.client.createCSV(
                name: fileName,
                parentID: parentID,
                data: data,
                accessToken: token
            )
        }
        setFileID(createdID, for: relativePath)
    }

    private func ensureLayout() async throws {
        if layout?.rootFolderId.isEmpty == false,
           layout?.folders["samples"] != nil,
           layout?.folders["workouts"] != nil,
           layout?.folders["manifests"] != nil
        {
            return
        }

        let rootID = try await findOrCreateFolder(name: "HealthSync", parentID: "root")
        let samplesID = try await findOrCreateFolder(name: "samples", parentID: rootID)
        let workoutsID = try await findOrCreateFolder(name: "workouts", parentID: rootID)
        let manifestsID = try await findOrCreateFolder(name: "manifests", parentID: rootID)

        var next = layout ?? DriveLayout(
            accountEmail: accountEmail,
            rootFolderId: rootID,
            folders: [:],
            files: [:]
        )
        next.accountEmail = accountEmail
        next.rootFolderId = rootID
        next.folders["samples"] = samplesID
        next.folders["workouts"] = workoutsID
        next.folders["manifests"] = manifestsID
        persist(next)
    }

    private func findOrCreateFolder(name: String, parentID: String) async throws -> String {
        let query = """
        name = '\(name)' and mimeType = 'application/vnd.google-apps.folder' and '\(parentID)' in parents and trashed = false
        """
        let matches = try await withAuthorizedToken { token in
            try await self.client.findFiles(query: query, accessToken: token)
        }
        if let existing = matches.first {
            return existing.id
        }
        return try await withAuthorizedToken { token in
            try await self.client.createFolder(name: name, parentID: parentID, accessToken: token)
        }
    }

    private func folderID(named name: String) throws -> String {
        guard let id = layout?.folders[name] else {
            throw DriveClientError.invalidResponse
        }
        return id
    }

    private func setFileID(_ id: String, for path: String) {
        var next = layout ?? DriveLayout(
            accountEmail: accountEmail,
            rootFolderId: "",
            folders: [:],
            files: [:]
        )
        next.files[path] = id
        persist(next)
    }

    private func removeFileID(for path: String) {
        guard var next = layout else { return }
        next.files.removeValue(forKey: path)
        persist(next)
    }

    private func persist(_ layout: DriveLayout) {
        self.layout = layout
        layoutStore.save(layout)
    }

    private func withAuthorizedToken<T: Sendable>(
        _ work: @Sendable (String) async throws -> T
    ) async throws -> T {
        do {
            return try await work(try await tokenProvider())
        } catch DriveClientError.unauthorized {
            return try await work(try await tokenProvider())
        }
    }
}

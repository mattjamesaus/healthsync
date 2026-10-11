import Foundation

struct DriveFileRef: Sendable {
    let id: String
    let name: String
}

enum DriveClientError: LocalizedError {
    case invalidURL
    case httpStatus(Int, String?)
    case missingUploadURL
    case invalidResponse
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build a Google Drive request."
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "Google Drive request failed (\(code)): \(message)"
            }
            return "Google Drive request failed (\(code))."
        case .missingUploadURL:
            return "Google Drive did not return an upload URL."
        case .invalidResponse:
            return "Google Drive returned an unexpected response."
        case .unauthorized:
            return "Open HealthSync and reconnect Google Drive."
        }
    }
}

struct DriveClient: Sendable {
    private let session: URLSession
    private let metadataBase = URL(string: "https://www.googleapis.com/drive/v3")!
    private let uploadBase = URL(string: "https://www.googleapis.com/upload/drive/v3")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func findFiles(query: String, accessToken: String) async throws -> [DriveFileRef] {
        var components = URLComponents(
            url: metadataBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "10"),
            URLQueryItem(name: "spaces", value: "drive"),
        ]
        guard let url = components?.url else { throw DriveClientError.invalidURL }

        let data = try await send(
            request(url: url, method: "GET", accessToken: accessToken)
        )
        let decoded = try JSONDecoder().decode(FileListResponse.self, from: data)
        return (decoded.files ?? []).compactMap { file in
            guard let id = file.id, let name = file.name else { return nil }
            return DriveFileRef(id: id, name: name)
        }
    }

    func createFolder(name: String, parentID: String, accessToken: String) async throws -> String {
        let url = metadataBase.appendingPathComponent("files")
        var request = request(url: url, method: "POST", accessToken: accessToken)
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "name": name,
                "mimeType": "application/vnd.google-apps.folder",
                "parents": [parentID],
            ]
        )
        let data = try await send(request)
        return try decodeID(from: data)
    }

    func download(fileID: String, accessToken: String) async throws -> Data? {
        var components = URLComponents(
            url: metadataBase.appendingPathComponent("files/\(fileID)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "alt", value: "media")]
        guard let url = components?.url else { throw DriveClientError.invalidURL }

        do {
            return try await send(request(url: url, method: "GET", accessToken: accessToken))
        } catch DriveClientError.httpStatus(404, _) {
            return nil
        }
    }

    func createCSV(name: String, parentID: String, data: Data, accessToken: String) async throws -> String {
        let metadata: [String: Any] = [
            "name": name,
            "parents": [parentID],
            "mimeType": "text/csv",
        ]
        let sessionURL = try await startResumableUpload(
            path: "files",
            method: "POST",
            metadata: metadata,
            contentType: "text/csv",
            contentLength: data.count,
            accessToken: accessToken
        )
        return try decodeID(from: try await uploadBytes(to: sessionURL, data: data, contentType: "text/csv"))
    }

    func updateCSV(fileID: String, data: Data, accessToken: String) async throws {
        let sessionURL = try await startResumableUpload(
            path: "files/\(fileID)",
            method: "PATCH",
            metadata: [:],
            contentType: "text/csv",
            contentLength: data.count,
            accessToken: accessToken
        )
        _ = try await uploadBytes(to: sessionURL, data: data, contentType: "text/csv")
    }

    func createJSON(name: String, parentID: String, data: Data, accessToken: String) async throws -> String {
        let boundary = "healthsync_\(UUID().uuidString)"
        var components = URLComponents(
            url: uploadBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: "id,name"),
        ]
        guard let url = components?.url else { throw DriveClientError.invalidURL }

        let metadata = try JSONSerialization.data(
            withJSONObject: [
                "name": name,
                "parents": [parentID],
                "mimeType": "application/json",
            ]
        )

        var body = Data()
        body.append(utf8: "--\(boundary)\r\n")
        body.append(utf8: "Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadata)
        body.append(utf8: "\r\n--\(boundary)\r\n")
        body.append(utf8: "Content-Type: application/json\r\n\r\n")
        body.append(data)
        body.append(utf8: "\r\n--\(boundary)--\r\n")

        var request = request(url: url, method: "POST", accessToken: accessToken)
        request.setValue(
            "multipart/related; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        return try decodeID(from: try await send(request))
    }

    private func startResumableUpload(
        path: String,
        method: String,
        metadata: [String: Any],
        contentType: String,
        contentLength: Int,
        accessToken: String
    ) async throws -> URL {
        var components = URLComponents(
            url: uploadBase.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "fields", value: "id,name"),
        ]
        guard let url = components?.url else { throw DriveClientError.invalidURL }

        var request = request(url: url, method: method, accessToken: accessToken)
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(contentType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(contentLength), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (_, response) = try await rawSend(request)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location)
        else {
            throw DriveClientError.missingUploadURL
        }
        return uploadURL
    }

    private func uploadBytes(to url: URL, data: Data, contentType: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = data
        return try await send(request)
    }

    private func request(url: URL, method: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await rawSend(request)
        return data
    }

    private func rawSend(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DriveClientError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401:
            throw DriveClientError.unauthorized
        default:
            throw DriveClientError.httpStatus(http.statusCode, driveMessage(from: data))
        }
    }

    private func decodeID(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(FileResource.self, from: data)
        guard let id = decoded.id else { throw DriveClientError.invalidResponse }
        return id
    }

    private func driveMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any]
        else {
            return nil
        }
        return error["message"] as? String
    }
}

private struct FileListResponse: Decodable {
    let files: [FileResource]?
}

private struct FileResource: Decodable {
    let id: String?
    let name: String?
}

private extension Data {
    mutating func append(utf8 string: String) {
        append(Data(string.utf8))
    }
}

import Foundation
import GoogleSignIn
import UIKit

enum GoogleAuthError: LocalizedError {
    case missingClientID
    case notSignedIn
    case missingDriveScope
    case noPresentingViewController

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Google Sign-In is not configured. Add the iOS client ID to Config/Google.local.xcconfig."
        case .notSignedIn, .missingDriveScope:
            return "Open HealthSync and reconnect Google Drive."
        case .noPresentingViewController:
            return "Could not present Google Sign-In."
        }
    }
}

enum GoogleAuth {
    static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    static func configure() {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty
        else {
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    @MainActor
    static func signIn() async throws -> GIDGoogleUser {
        configure()
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty
        else {
            throw GoogleAuthError.missingClientID
        }
        guard let presenter = presentingViewController() else {
            throw GoogleAuthError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: [driveFileScope]
        )
        try requireDriveScope(result.user)
        return result.user
    }

    @discardableResult
    static func restoreSession() async throws -> GIDGoogleUser {
        configure()
        let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        let refreshed = try await refresh(user)
        try requireDriveScope(refreshed)
        return refreshed
    }

    static func accessToken() async throws -> String {
        let user = try await restoreSession()
        return user.accessToken.tokenString
    }

    static func refresh(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshed, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let refreshed else {
                    continuation.resume(throwing: GoogleAuthError.notSignedIn)
                    return
                }
                continuation.resume(returning: refreshed)
            }
        }
    }

    static func requireDriveScope(_ user: GIDGoogleUser) throws {
        let scopes = user.grantedScopes ?? []
        let hasDrive = scopes.contains { scope in
            scope == driveFileScope || scope.hasSuffix("/auth/drive.file")
        }
        guard hasDrive else {
            throw GoogleAuthError.missingDriveScope
        }
    }

    static func disconnect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.disconnect { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    static func presentingViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

@MainActor
final class GoogleAuthStore: ObservableObject {
    @Published private(set) var accountEmail: String?
    @Published private(set) var isConnected = false
    @Published var isWorking = false

    func restore() async {
        do {
            let user = try await GoogleAuth.restoreSession()
            apply(user)
        } catch {
            accountEmail = nil
            isConnected = false
        }
    }

    func connect() async throws {
        isWorking = true
        defer { isWorking = false }
        let user = try await GoogleAuth.signIn()
        apply(user)
    }

    func disconnect() async throws {
        isWorking = true
        defer { isWorking = false }
        try await GoogleAuth.disconnect()
        accountEmail = nil
        isConnected = false
    }

    private func apply(_ user: GIDGoogleUser) {
        accountEmail = user.profile?.email
        isConnected = true
    }
}

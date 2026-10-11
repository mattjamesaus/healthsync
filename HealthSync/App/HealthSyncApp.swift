import Sentry
import SwiftUI

@main
struct HealthSyncApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        Self.startSentry()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
    }

    /// DSN is the SentryDSN Info.plist value, substituted from Config/Secrets.xcconfig.
    private static func startSentry() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              dsn.hasPrefix("https://") else {
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.debug = true
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
            options.tracesSampleRate = 1.0

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            if let bundleId = Bundle.main.bundleIdentifier {
                options.releaseName = "\(bundleId)@\(version)+\(build)"
            }
        }
    }
}

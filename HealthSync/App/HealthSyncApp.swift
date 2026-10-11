import GoogleSignIn
import Sentry
import SwiftUI

@main
struct HealthSyncApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        GoogleAuth.configure()
        Self.startSentry()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
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
            options.sendDefaultPii = false

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            if let bundleId = Bundle.main.bundleIdentifier {
                options.releaseName = "\(bundleId)@\(version)+\(build)"
            }

            options.beforeSend = { event in
                event.request?.headers?.removeValue(forKey: "Authorization")
                event.request?.headers?.removeValue(forKey: "authorization")
                event.request?.cookies = nil
                return event
            }
            options.beforeBreadcrumb = { crumb in
                crumb.data?.removeValue(forKey: "Authorization")
                crumb.data?.removeValue(forKey: "authorization")
                crumb.data?.removeValue(forKey: "request_body")
                crumb.data?.removeValue(forKey: "response_body")
                return crumb
            }
        }
    }
}

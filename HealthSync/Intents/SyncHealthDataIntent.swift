import AppIntents
import Foundation
import Sentry

struct SyncHealthDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Health Data"
    static var description = IntentDescription(
        "Incrementally export HealthKit samples and workouts to Google Drive."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let watermarks = WatermarkStore()
        let metrics = MetricSelectionStore()

        do {
            let user = try await GoogleAuth.restoreSession()
            let destination = DriveDestination(
                accountEmail: user.profile?.email ?? ""
            )
            let result = try await ExportPipeline.shared.sync(
                destination: destination,
                metrics: metrics.enabledMetrics,
                existingWatermark: watermarks.watermark
            )
            watermarks.advance(to: result.watermarkAfter)
            return .result(value: result.summary)
        } catch {
            if !(error is ExportPipelineError), !(error is GoogleAuthError) {
                SentrySDK.capture(error: error)
            }
            throw error
        }
    }
}

struct HealthSyncShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncHealthDataIntent(),
            phrases: [
                "Sync health data with \(.applicationName)",
                "Run \(.applicationName) sync",
            ],
            shortTitle: "Sync Health Data",
            systemImageName: "heart.text.square"
        )
    }
}

import AppIntents
import Foundation
import Sentry

struct SyncHealthDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Health Data"
    static var description = IntentDescription(
        "Incrementally export HealthKit samples and workouts to your saved Health Sync folder."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let bookmarks = BookmarkStore()
        let watermarks = WatermarkStore()
        let metrics = MetricSelectionStore()

        do {
            let resolved = try bookmarks.resolveAccessibleURL()
            defer { resolved.stopAccessing() }

            let result = try await ExportPipeline.shared.sync(
                destination: resolved.url,
                metrics: metrics.enabledMetrics,
                existingWatermark: watermarks.watermark
            )
            watermarks.advance(to: result.watermarkAfter)
            return .result(value: result.summary)
        } catch {
            // Always surface failure to Shortcuts instead of hanging.
            // Validation failures stay in the shortcut result; unexpected failures go to Sentry.
            if !(error is ExportPipelineError) {
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

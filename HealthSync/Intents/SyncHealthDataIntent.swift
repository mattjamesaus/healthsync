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
            let layoutStore = DriveLayoutStore.shared
            let existingWatermark = layoutStore.hasUploadedExportFiles
                ? watermarks.watermark
                : nil
            let result = try await ExportPipeline.shared.sync(
                destination: destination,
                metrics: metrics.enabledMetrics,
                existingWatermark: existingWatermark
            )
            let wroteRows = result.sampleRowsWritten + result.workoutRowsWritten > 0
            let shouldAdvance = wroteRows || existingWatermark != nil
            watermarks.recordCompletion(
                advancingWatermarkTo: shouldAdvance ? result.watermarkAfter : nil
            )
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

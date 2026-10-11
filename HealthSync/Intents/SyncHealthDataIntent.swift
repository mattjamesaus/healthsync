import AppIntents
import Foundation

struct SyncHealthDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Health Data"
    static var description = IntentDescription(
        "Incrementally export HealthKit samples and workouts to your saved HealthSync folder."
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

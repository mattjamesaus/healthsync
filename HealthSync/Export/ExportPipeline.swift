import Foundation

struct SyncResult: Sendable {
    let sampleRowsWritten: Int
    let workoutRowsWritten: Int
    let windowStart: Date
    let windowEnd: Date
    let watermarkAfter: Date
    let destinationName: String

    var summary: String {
        "Synced \(sampleRowsWritten) samples, \(workoutRowsWritten) workouts. Watermark \(ISO8601DateFormatter.export.string(from: watermarkAfter))."
    }
}

enum ExportPipelineError: LocalizedError {
    case noMetricsSelected
    case healthUnavailable

    var errorDescription: String? {
        switch self {
        case .noMetricsSelected:
            return "Select at least one health metric to sync."
        case .healthUnavailable:
            return "Health data is not available on this device."
        }
    }
}

/// Orchestrates incremental HealthKit → CSV export into a bookmarked folder.
final class ExportPipeline: @unchecked Sendable {
    static let shared = ExportPipeline()

    private let healthClient: HealthKitClient
    private let overlap: TimeInterval = 5 * 60 // 5 minutes
    private let defaultBackfillDays = 30

    init(healthClient: HealthKitClient = HealthKitClient()) {
        self.healthClient = healthClient
    }

    func sync(
        destination: URL,
        metrics: [MetricDefinition],
        existingWatermark: Date?
    ) async throws -> SyncResult {
        guard !metrics.isEmpty else {
            throw ExportPipelineError.noMetricsSelected
        }
        guard HealthKitClient.isHealthDataAvailable else {
            throw ExportPipelineError.healthUnavailable
        }

        let windowEnd = Date()
        let windowStart: Date
        if let watermark = existingWatermark {
            windowStart = watermark.addingTimeInterval(-overlap)
        } else {
            windowStart = Calendar.current.date(
                byAdding: .day,
                value: -defaultBackfillDays,
                to: windowEnd
            ) ?? windowEnd.addingTimeInterval(-Double(defaultBackfillDays) * 24 * 3600)
        }

        try await healthClient.requestAuthorization(for: metrics)

        var allSamples: [SampleRow] = []
        var allWorkouts: [WorkoutRow] = []

        for metric in metrics {
            switch metric.kind {
            case .quantity:
                let rows = try await healthClient.fetchQuantitySamples(
                    for: metric,
                    start: windowStart,
                    end: windowEnd
                )
                allSamples.append(contentsOf: rows)
            case .category:
                let rows = try await healthClient.fetchCategorySamples(
                    for: metric,
                    start: windowStart,
                    end: windowEnd
                )
                allSamples.append(contentsOf: rows)
            case .workout:
                let rows = try await healthClient.fetchWorkouts(
                    start: windowStart,
                    end: windowEnd
                )
                allWorkouts.append(contentsOf: rows)
            }
        }

        let samplesDir = destination.appendingPathComponent("samples", isDirectory: true)
        let workoutsDir = destination.appendingPathComponent("workouts", isDirectory: true)
        let manifestsDir = destination.appendingPathComponent("manifests", isDirectory: true)

        var samplesWritten = 0
        let samplesByMonth = Dictionary(grouping: allSamples) { MonthKey.from($0.start) }
        for (month, rows) in samplesByMonth {
            samplesWritten += try CSVWriter.appendSamples(
                rows,
                to: samplesDir,
                monthKey: month
            )
        }

        var workoutsWritten = 0
        let workoutsByMonth = Dictionary(grouping: allWorkouts) { MonthKey.from($0.start) }
        for (month, rows) in workoutsByMonth {
            workoutsWritten += try CSVWriter.appendWorkouts(
                rows,
                to: workoutsDir,
                monthKey: month
            )
        }

        let watermarkAfter = windowEnd
        let destinationName = destination.lastPathComponent

        let manifest = SyncManifest(
            syncedAt: CSVWriter.iso8601(Date()),
            windowStart: CSVWriter.iso8601(windowStart),
            windowEnd: CSVWriter.iso8601(windowEnd),
            watermarkAfter: CSVWriter.iso8601(watermarkAfter),
            sampleRowsWritten: samplesWritten,
            workoutRowsWritten: workoutsWritten,
            metrics: metrics.map(\.id),
            destination: destinationName,
            notes: existingWatermark == nil
                ? "Initial backfill (\(defaultBackfillDays) days)."
                : nil
        )
        _ = try SyncManifestWriter.write(manifest, to: manifestsDir)

        return SyncResult(
            sampleRowsWritten: samplesWritten,
            workoutRowsWritten: workoutsWritten,
            windowStart: windowStart,
            windowEnd: windowEnd,
            watermarkAfter: watermarkAfter,
            destinationName: destinationName
        )
    }
}

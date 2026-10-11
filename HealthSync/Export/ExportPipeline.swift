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

/// Orchestrates incremental HealthKit → CSV export into a destination.
final class ExportPipeline: @unchecked Sendable {
    static let shared = ExportPipeline()

    private let healthClient: HealthKitClient
    private let overlap: TimeInterval = 5 * 60 // 5 minutes
    private let defaultBackfillDays = 30

    init(healthClient: HealthKitClient = HealthKitClient()) {
        self.healthClient = healthClient
    }

    func sync(
        destination: SyncDestination,
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

        var samplesWritten = 0
        let samplesByMonth = Dictionary(grouping: allSamples) { MonthKey.from($0.start) }
        for (month, rows) in samplesByMonth {
            let path = "samples/\(month).csv"
            let existing = try await destination.read(relativePath: path)
            let merged = CSVWriter.mergeSamples(rows, existing: existing)
            if merged.added > 0 {
                try await destination.write(
                    relativePath: path,
                    data: merged.data,
                    mimeType: "text/csv"
                )
            }
            samplesWritten += merged.added
        }

        var workoutsWritten = 0
        let workoutsByMonth = Dictionary(grouping: allWorkouts) { MonthKey.from($0.start) }
        for (month, rows) in workoutsByMonth {
            let path = "workouts/\(month).csv"
            let existing = try await destination.read(relativePath: path)
            let merged = CSVWriter.mergeWorkouts(rows, existing: existing)
            if merged.added > 0 {
                try await destination.write(
                    relativePath: path,
                    data: merged.data,
                    mimeType: "text/csv"
                )
            }
            workoutsWritten += merged.added
        }

        let watermarkAfter = windowEnd
        let destinationName = destination.displayName

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
        let encoded = try SyncManifestWriter.encode(manifest)
        try await destination.write(
            relativePath: "manifests/\(encoded.fileName)",
            data: encoded.data,
            mimeType: "application/json"
        )

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

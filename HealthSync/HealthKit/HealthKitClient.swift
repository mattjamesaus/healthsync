import Foundation
import HealthKit

struct SampleRow: Sendable, Hashable {
    let start: Date
    let end: Date
    let type: String
    let unit: String
    let value: String
    let source: String
    let uuid: String
}

struct WorkoutRow: Sendable, Hashable {
    let start: Date
    let end: Date
    let workoutType: String
    let durationSeconds: Double
    let totalEnergyKilocalories: Double?
    let totalDistanceMeters: Double?
    let source: String
    let uuid: String
}

enum HealthKitClientError: LocalizedError {
    case healthDataUnavailable
    case authorizationFailed(String)
    case invalidType(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this device."
        case .authorizationFailed(let message):
            return "Health authorization failed: \(message)"
        case .invalidType(let id):
            return "Unsupported health type: \(id)"
        }
    }
}

actor HealthKitClient {
    private let store: HKHealthStore
    private let pageSize = 1_000

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization(for metrics: [MetricDefinition]) async throws {
        guard Self.isHealthDataAvailable else {
            throw HealthKitClientError.healthDataUnavailable
        }

        var types: Set<HKObjectType> = []
        for metric in metrics {
            guard let objectType = metric.objectType else {
                throw HealthKitClientError.invalidType(metric.id)
            }
            types.insert(objectType)
        }

        // Do not gate on authorizationStatus — read grants often remain .sharingDenied.
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func fetchQuantitySamples(
        for metric: MetricDefinition,
        start: Date,
        end: Date
    ) async throws -> [SampleRow] {
        guard metric.kind == .quantity,
              let identifier = metric.quantityTypeIdentifier,
              let quantityType = HKObjectType.quantityType(forIdentifier: identifier)
        else {
            throw HealthKitClientError.invalidType(metric.id)
        }

        let unit = try await preferredUnit(for: quantityType)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )

        var collected: [SampleRow] = []
        var anchor: HKQueryAnchor?

        while true {
            let page = try await anchoredSamplePage(
                sampleType: quantityType,
                predicate: predicate,
                anchor: anchor
            )
            anchor = page.anchor

            for sample in page.added {
                guard let quantitySample = sample as? HKQuantitySample else { continue }
                let value = quantitySample.quantity.doubleValue(for: unit)
                collected.append(
                    SampleRow(
                        start: quantitySample.startDate,
                        end: quantitySample.endDate,
                        type: metric.id,
                        unit: unit.unitString,
                        value: formatNumber(value),
                        source: quantitySample.sourceRevision.source.name,
                        uuid: quantitySample.uuid.uuidString
                    )
                )
            }

            if page.added.count < pageSize {
                break
            }
        }

        return collected.sorted { $0.start < $1.start }
    }

    func fetchCategorySamples(
        for metric: MetricDefinition,
        start: Date,
        end: Date
    ) async throws -> [SampleRow] {
        guard metric.kind == .category,
              let identifier = metric.categoryTypeIdentifier,
              let categoryType = HKObjectType.categoryType(forIdentifier: identifier)
        else {
            throw HealthKitClientError.invalidType(metric.id)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )

        var collected: [SampleRow] = []
        var anchor: HKQueryAnchor?

        while true {
            let page = try await anchoredSamplePage(
                sampleType: categoryType,
                predicate: predicate,
                anchor: anchor
            )
            anchor = page.anchor

            for sample in page.added {
                guard let categorySample = sample as? HKCategorySample else { continue }
                let valueLabel = sleepValueLabel(
                    for: categorySample,
                    identifier: identifier
                )
                collected.append(
                    SampleRow(
                        start: categorySample.startDate,
                        end: categorySample.endDate,
                        type: metric.id,
                        unit: "category",
                        value: valueLabel,
                        source: categorySample.sourceRevision.source.name,
                        uuid: categorySample.uuid.uuidString
                    )
                )
            }

            if page.added.count < pageSize {
                break
            }
        }

        return collected.sorted { $0.start < $1.start }
    }

    func fetchWorkouts(start: Date, end: Date) async throws -> [WorkoutRow] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )

        var collected: [WorkoutRow] = []
        var anchor: HKQueryAnchor?

        while true {
            let page = try await anchoredSamplePage(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                anchor: anchor
            )
            anchor = page.anchor

            for sample in page.added {
                guard let workout = sample as? HKWorkout else { continue }
                let energy = workout.totalEnergyBurned?
                    .doubleValue(for: .kilocalorie())
                let distance = workout.totalDistance?
                    .doubleValue(for: .meter())
                collected.append(
                    WorkoutRow(
                        start: workout.startDate,
                        end: workout.endDate,
                        workoutType: workoutActivityName(workout.workoutActivityType),
                        durationSeconds: workout.duration,
                        totalEnergyKilocalories: energy,
                        totalDistanceMeters: distance,
                        source: workout.sourceRevision.source.name,
                        uuid: workout.uuid.uuidString
                    )
                )
            }

            if page.added.count < pageSize {
                break
            }
        }

        return collected.sorted { $0.start < $1.start }
    }

    private func preferredUnit(for type: HKQuantityType) async throws -> HKUnit {
        do {
            let units = try await store.preferredUnits(for: [type])
            if let unit = units[type] {
                return unit
            }
        } catch {
            // Fall through to defaults.
        }

        return fallbackUnit(for: type)
    }

    private func fallbackUnit(for type: HKQuantityType) -> HKUnit {
        let identifier = HKQuantityTypeIdentifier(rawValue: type.identifier)
        switch identifier {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage:
            return HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN:
            return .secondUnit(with: .milli)
        case .vo2Max:
            return HKUnit.literUnit(with: .milli)
                .unitDivided(by: .gramUnit(with: .kilo))
                .unitDivided(by: .minute())
        case .activeEnergyBurned, .basalEnergyBurned:
            return .kilocalorie()
        case .distanceWalkingRunning:
            return .meter()
        case .appleExerciseTime, .appleStandTime:
            return .minute()
        case .stepCount, .flightsClimbed:
            return .count()
        case .bodyMass:
            return .gramUnit(with: .kilo)
        case .bodyFatPercentage, .oxygenSaturation:
            return .percent()
        case .respiratoryRate:
            return HKUnit.count().unitDivided(by: .minute())
        default:
            return .count()
        }
    }

    private func sleepValueLabel(
        for sample: HKCategorySample,
        identifier: HKCategoryTypeIdentifier
    ) -> String {
        guard identifier == .sleepAnalysis else {
            return String(sample.value)
        }

        if let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            switch value {
            case .inBed: return "inBed"
            case .asleepUnspecified: return "asleepUnspecified"
            case .awake: return "awake"
            case .asleepCore: return "asleepCore"
            case .asleepDeep: return "asleepDeep"
            case .asleepREM: return "asleepREM"
            @unknown default: return "unknown(\(sample.value))"
            }
        }
        return String(sample.value)
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.6g", value)
    }

    private struct AnchoredPage {
        let added: [HKSample]
        let deleted: [HKDeletedObject]
        let anchor: HKQueryAnchor?
    }

    private func anchoredSamplePage(
        sampleType: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?
    ) async throws -> AnchoredPage {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: predicate,
                anchor: anchor,
                limit: pageSize
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(
                    returning: AnchoredPage(
                        added: samples ?? [],
                        deleted: deleted ?? [],
                        anchor: newAnchor
                    )
                )
            }
            store.execute(query)
        }
    }
}

private func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
    switch type {
    case .running: return "running"
    case .cycling: return "cycling"
    case .walking: return "walking"
    case .hiking: return "hiking"
    case .swimming: return "swimming"
    case .traditionalStrengthTraining: return "traditionalStrengthTraining"
    case .functionalStrengthTraining: return "functionalStrengthTraining"
    case .yoga: return "yoga"
    case .pilates: return "pilates"
    case .highIntensityIntervalTraining: return "highIntensityIntervalTraining"
    case .elliptical: return "elliptical"
    case .rowing: return "rowing"
    case .stairClimbing: return "stairClimbing"
    case .dance: return "dance"
    case .cooldown: return "cooldown"
    case .coreTraining: return "coreTraining"
    case .flexibility: return "flexibility"
    case .mixedCardio: return "mixedCardio"
    case .other: return "other"
    default: return String(describing: type)
    }
}

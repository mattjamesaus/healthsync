import Foundation
import HealthKit

enum MetricKind: String, Codable, Hashable, CaseIterable {
    case quantity
    case category
    case workout
}

struct MetricDefinition: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let group: String
    let kind: MetricKind
    let quantityIdentifier: String?
    let categoryIdentifier: String?
    let defaultEnabled: Bool

    var quantityTypeIdentifier: HKQuantityTypeIdentifier? {
        guard let quantityIdentifier else { return nil }
        return HKQuantityTypeIdentifier(rawValue: quantityIdentifier)
    }

    var categoryTypeIdentifier: HKCategoryTypeIdentifier? {
        guard let categoryIdentifier else { return nil }
        return HKCategoryTypeIdentifier(rawValue: categoryIdentifier)
    }

    var objectType: HKObjectType? {
        switch kind {
        case .quantity:
            guard let quantityTypeIdentifier else { return nil }
            return HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier)
        case .category:
            guard let categoryTypeIdentifier else { return nil }
            return HKObjectType.categoryType(forIdentifier: categoryTypeIdentifier)
        case .workout:
            return HKObjectType.workoutType()
        }
    }
}

enum MetricCatalog {
    static let all: [MetricDefinition] = [
        // Workouts
        MetricDefinition(
            id: "workout",
            displayName: "Workouts",
            group: "Fitness",
            kind: .workout,
            quantityIdentifier: nil,
            categoryIdentifier: nil,
            defaultEnabled: true
        ),

        // Fitness quantities
        metric(
            id: HKQuantityTypeIdentifier.stepCount.rawValue,
            name: "Steps",
            group: "Fitness",
            quantity: .stepCount
        ),
        metric(
            id: HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
            name: "Walking + Running Distance",
            group: "Fitness",
            quantity: .distanceWalkingRunning
        ),
        metric(
            id: HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            name: "Active Energy",
            group: "Fitness",
            quantity: .activeEnergyBurned
        ),
        metric(
            id: HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
            name: "Basal Energy",
            group: "Fitness",
            quantity: .basalEnergyBurned
        ),
        metric(
            id: HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
            name: "Exercise Time",
            group: "Fitness",
            quantity: .appleExerciseTime
        ),
        metric(
            id: HKQuantityTypeIdentifier.appleStandTime.rawValue,
            name: "Stand Time",
            group: "Fitness",
            quantity: .appleStandTime
        ),
        metric(
            id: HKQuantityTypeIdentifier.flightsClimbed.rawValue,
            name: "Flights Climbed",
            group: "Fitness",
            quantity: .flightsClimbed
        ),

        // Heart
        metric(
            id: HKQuantityTypeIdentifier.heartRate.rawValue,
            name: "Heart Rate",
            group: "Heart",
            quantity: .heartRate
        ),
        metric(
            id: HKQuantityTypeIdentifier.restingHeartRate.rawValue,
            name: "Resting Heart Rate",
            group: "Heart",
            quantity: .restingHeartRate
        ),
        metric(
            id: HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
            name: "Heart Rate Variability",
            group: "Heart",
            quantity: .heartRateVariabilitySDNN
        ),
        metric(
            id: HKQuantityTypeIdentifier.walkingHeartRateAverage.rawValue,
            name: "Walking Heart Rate Average",
            group: "Heart",
            quantity: .walkingHeartRateAverage
        ),
        metric(
            id: HKQuantityTypeIdentifier.vo2Max.rawValue,
            name: "VO2 Max",
            group: "Heart",
            quantity: .vo2Max
        ),

        // Sleep
        MetricDefinition(
            id: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
            displayName: "Sleep Analysis",
            group: "Sleep",
            kind: .category,
            quantityIdentifier: nil,
            categoryIdentifier: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
            defaultEnabled: true
        ),

        // Body
        metric(
            id: HKQuantityTypeIdentifier.bodyMass.rawValue,
            name: "Body Mass",
            group: "Body",
            quantity: .bodyMass
        ),
        metric(
            id: HKQuantityTypeIdentifier.bodyFatPercentage.rawValue,
            name: "Body Fat Percentage",
            group: "Body",
            quantity: .bodyFatPercentage
        ),

        // Vitals
        metric(
            id: HKQuantityTypeIdentifier.oxygenSaturation.rawValue,
            name: "Oxygen Saturation",
            group: "Vitals",
            quantity: .oxygenSaturation,
            defaultEnabled: false
        ),
        metric(
            id: HKQuantityTypeIdentifier.respiratoryRate.rawValue,
            name: "Respiratory Rate",
            group: "Vitals",
            quantity: .respiratoryRate,
            defaultEnabled: false
        ),
    ]

    static var grouped: [(String, [MetricDefinition])] {
        let order = ["Fitness", "Heart", "Sleep", "Body", "Vitals"]
        let byGroup = Dictionary(grouping: all, by: \.group)
        return order.compactMap { group in
            guard let metrics = byGroup[group], !metrics.isEmpty else { return nil }
            return (group, metrics)
        }
    }

    static var defaultEnabledIDs: Set<String> {
        Set(all.filter(\.defaultEnabled).map(\.id))
    }

    static func metric(id: String) -> MetricDefinition? {
        all.first { $0.id == id }
    }

    private static func metric(
        id: String,
        name: String,
        group: String,
        quantity: HKQuantityTypeIdentifier,
        defaultEnabled: Bool = true
    ) -> MetricDefinition {
        MetricDefinition(
            id: id,
            displayName: name,
            group: group,
            kind: .quantity,
            quantityIdentifier: quantity.rawValue,
            categoryIdentifier: nil,
            defaultEnabled: defaultEnabled
        )
    }
}

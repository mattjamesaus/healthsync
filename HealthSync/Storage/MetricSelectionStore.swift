import Foundation

@MainActor
final class MetricSelectionStore: ObservableObject {
    private let key = "enabledMetricIDs"
    private let defaults: UserDefaults

    @Published private(set) var enabledIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        {
            enabledIDs = decoded
        } else {
            enabledIDs = MetricCatalog.defaultEnabledIDs
            persist(MetricCatalog.defaultEnabledIDs)
        }
    }

    var enabledMetrics: [MetricDefinition] {
        MetricCatalog.all.filter { enabledIDs.contains($0.id) }
    }

    func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    func toggle(_ id: String) {
        var next = enabledIDs
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        enabledIDs = next
        persist(next)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        var next = enabledIDs
        if enabled {
            next.insert(id)
        } else {
            next.remove(id)
        }
        enabledIDs = next
        persist(next)
    }

    private func persist(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: key)
        }
    }
}

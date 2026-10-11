import Foundation

@MainActor
final class WatermarkStore: ObservableObject {
    private let watermarkKey = "lastSuccessfulSyncAt"
    private let lastSyncDisplayKey = "lastSyncCompletedAt"
    private let defaults: UserDefaults

    /// Exclusive lower bound for the next sync window (samples with start >= watermark - overlap).
    @Published private(set) var watermark: Date?
    @Published private(set) var lastSyncCompletedAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        if let interval = defaults.object(forKey: watermarkKey) as? Double {
            watermark = Date(timeIntervalSince1970: interval)
        } else {
            watermark = nil
        }
        if let interval = defaults.object(forKey: lastSyncDisplayKey) as? Double {
            lastSyncCompletedAt = Date(timeIntervalSince1970: interval)
        } else {
            lastSyncCompletedAt = nil
        }
    }

    func advance(to date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: watermarkKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastSyncDisplayKey)
        reload()
    }

    func reset() {
        defaults.removeObject(forKey: watermarkKey)
        defaults.removeObject(forKey: lastSyncDisplayKey)
        reload()
    }
}

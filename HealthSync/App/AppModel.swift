import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let bookmarks = BookmarkStore()
    let watermarks = WatermarkStore()
    let metricSelection = MetricSelectionStore()

    @Published var isSyncing = false
    @Published var lastResultMessage: String?
    @Published var lastErrorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        bookmarks.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        watermarks.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        metricSelection.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        do {
            let resolved = try bookmarks.resolveAccessibleURL()
            defer { resolved.stopAccessing() }

            let result = try await ExportPipeline.shared.sync(
                destination: resolved.url,
                metrics: metricSelection.enabledMetrics,
                existingWatermark: watermarks.watermark
            )
            watermarks.advance(to: result.watermarkAfter)
            lastResultMessage = result.summary
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

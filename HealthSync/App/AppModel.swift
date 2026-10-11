import Combine
import Foundation
import Sentry
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let googleAuth = GoogleAuthStore()
    let watermarks = WatermarkStore()
    let metricSelection = MetricSelectionStore()
    let layoutStore = DriveLayoutStore.shared

    @Published var isSyncing = false
    @Published var lastResultMessage: String?
    @Published var lastErrorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        googleAuth.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        watermarks.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        metricSelection.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func restoreGoogleSession() async {
        await googleAuth.restore()
    }

    func connectGoogle() async {
        lastErrorMessage = nil
        do {
            try await googleAuth.connect()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func disconnectGoogle() async {
        lastErrorMessage = nil
        do {
            try await googleAuth.disconnect()
            layoutStore.clear()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        do {
            let user = try await GoogleAuth.restoreSession()
            let destination = DriveDestination(
                accountEmail: user.profile?.email ?? googleAuth.accountEmail ?? ""
            )
            let result = try await ExportPipeline.shared.sync(
                destination: destination,
                metrics: metricSelection.enabledMetrics,
                existingWatermark: watermarks.watermark
            )
            watermarks.advance(to: result.watermarkAfter)
            lastResultMessage = result.summary
        } catch {
            if !(error is ExportPipelineError), !(error is GoogleAuthError) {
                SentrySDK.capture(error: error)
            }
            lastErrorMessage = error.localizedDescription
        }
    }
}

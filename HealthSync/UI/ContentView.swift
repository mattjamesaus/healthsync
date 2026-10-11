import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            List {
                statusSection
                destinationSection
                syncSection
                metricsSection
                shortcutsSection
            }
            .navigationTitle("Health Sync")
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .task {
                await appModel.restoreGoogleSession()
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Google Drive") {
                Text(appModel.googleAuth.accountEmail ?? "Not connected")
                    .foregroundStyle(appModel.googleAuth.isConnected ? .primary : .secondary)
            }
            LabeledContent("Last sync") {
                Text(formatted(appModel.watermarks.lastSyncCompletedAt) ?? "Never")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Watermark") {
                Text(formatted(appModel.watermarks.watermark) ?? "None (next run backfills 30 days)")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if let message = appModel.lastResultMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = appModel.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var destinationSection: some View {
        Section("Google Drive") {
            if appModel.googleAuth.isConnected {
                Button("Disconnect", role: .destructive) {
                    Task { await appModel.disconnectGoogle() }
                }
                .disabled(appModel.googleAuth.isWorking)
            } else {
                Button {
                    Task { await appModel.connectGoogle() }
                } label: {
                    HStack {
                        Label("Connect Google Drive", systemImage: "person.crop.circle.badge.plus")
                        Spacer()
                        if appModel.googleAuth.isWorking {
                            ProgressView()
                        }
                    }
                }
                .disabled(appModel.googleAuth.isWorking)
            }
            Text(
                "Health Sync signs you into Google and writes CSV into My Drive/HealthSync. It does not use the Files app."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var syncSection: some View {
        Section {
            Button {
                Task { await appModel.sync() }
            } label: {
                HStack {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if appModel.isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(
                appModel.isSyncing
                    || !appModel.googleAuth.isConnected
                    || appModel.metricSelection.enabledMetrics.isEmpty
            )

            if appModel.watermarks.watermark != nil {
                Button("Reset watermark (next sync backfills 30 days)", role: .destructive) {
                    appModel.watermarks.reset()
                }
            }
        } header: {
            Text("Sync")
        }
    }

    private var metricsSection: some View {
        Section("Metrics") {
            ForEach(MetricCatalog.grouped, id: \.0) { group, items in
                DisclosureGroup(group) {
                    ForEach(items) { metric in
                        Toggle(
                            metric.displayName,
                            isOn: Binding(
                                get: { appModel.metricSelection.isEnabled(metric.id) },
                                set: { appModel.metricSelection.setEnabled(metric.id, $0) }
                            )
                        )
                    }
                }
            }
        }
    }

    private var shortcutsSection: some View {
        Section("Automation") {
            Text(
                "In the Shortcuts app, create an Automation → Time of Day → Run the “Sync Health Data” action from Health Sync. Optionally add a notification with the result."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                destinationSection
                syncSection
                metricsSection
                shortcutsSection
            }
            .navigationTitle("HealthSync")
            // Readable column width on iPad / landscape.
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderPick(result)
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Destination") {
                Text(appModel.bookmarks.displayName ?? "Not set")
                    .foregroundStyle(appModel.bookmarks.hasDestination ? .primary : .secondary)
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
        Section("Save folder") {
            Button {
                showingImporter = true
            } label: {
                Label(
                    appModel.bookmarks.hasDestination ? "Change folder…" : "Choose folder…",
                    systemImage: "folder"
                )
            }
            if appModel.bookmarks.hasDestination {
                Button("Clear saved folder", role: .destructive) {
                    appModel.bookmarks.clear()
                }
            }
            Text(
                "Pick an iCloud Drive or Google Drive folder in Files. HealthSync remembers it for Sync Now and Shortcuts."
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
                    || !appModel.bookmarks.hasDestination
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
                "In the Shortcuts app, create an Automation → Time of Day → Run the “Sync Health Data” action from HealthSync. Optionally add a notification with the result."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try appModel.bookmarks.save(folderURL: url)
                appModel.lastErrorMessage = nil
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            appModel.lastErrorMessage = error.localizedDescription
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

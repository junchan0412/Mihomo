import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedProfileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Profiles")
                        .font(.largeTitle.bold())
                    Text("SwiftUI manages profile workflows; the large profile table is AppKit-backed.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import Local...") {
                    importLocal()
                }
            }

            GroupBox("Remote Subscription") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("Name")
                        TextField("Optional", text: $store.newRemoteName)
                    }
                    GridRow {
                        Text("URL")
                        TextField("https://example.com/profile.yaml", text: $store.newRemoteURL)
                    }
                    GridRow {
                        Text("")
                        Button("Import Remote") {
                            Task { await store.addRemoteProfile() }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.vertical, 4)
            }

            HStack {
                Button("Activate") {
                    if let selected = selectedProfile {
                        Task { await store.setActiveProfile(selected) }
                    }
                }
                .disabled(selectedProfile == nil)

                Button("Refresh Selected") {
                    if let selected = selectedProfile {
                        Task { await store.refreshProfile(selected) }
                    }
                }
                .disabled(selectedProfile?.isRemote != true)

                Spacer()
            }

            AppKitTable(
                rows: store.profiles,
                selection: $selectedProfileID,
                columns: [
                    .init(title: "Name", width: 260) { profile in
                        (profile.id == store.settings.activeProfileID ? "* " : "") + profile.name
                    },
                    .init(title: "Type", width: 90) { $0.source.rawValue.capitalized },
                    .init(title: "Updated", width: 160) { Formatters.shortDate.string(from: $0.updatedAt) },
                    .init(title: "Usage", width: 220) { profile in
                        guard let total = profile.total else { return "-" }
                        let used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0)
                        return "\(Formatters.bytes(used)) / \(Formatters.bytes(total))"
                    }
                ]
            )
            .frame(minHeight: 360)
        }
        .padding(24)
        .navigationTitle("Profiles")
        .onAppear {
            selectedProfileID = store.settings.activeProfileID ?? store.profiles.first?.id
        }
    }

    private var selectedProfile: ProfileItem? {
        guard let selectedProfileID else { return nil }
        return store.profiles.first { $0.id == selectedProfileID }
    }

    private func importLocal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.importLocalProfile(url: url) }
        }
    }
}

private extension UTType {
    static let yaml = UTType(filenameExtension: "yaml") ?? .text
}

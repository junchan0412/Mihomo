import AppKit
import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default

    var body: some View {
        Form {
            Section("Core") {
                HStack {
                    TextField("mihomo binary", text: $draft.mihomoPath)
                    Button("Choose...") {
                        chooseMihomoBinary()
                    }
                }

                Picker("Log Level", selection: $draft.logLevel) {
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Warning").tag("warning")
                    Text("Error").tag("error")
                }
                .pickerStyle(.segmented)

                Toggle("Start core when Mihomo opens", isOn: $draft.autoStartCore)
            }

            Section("Controller") {
                TextField("Host", text: $draft.controllerHost)
                TextField("Controller Port", value: $draft.controllerPort, format: .number)
                TextField("Mixed Port", value: $draft.mixedPort, format: .number)
                TextField("SOCKS Port", value: $draft.socksPort, format: .number)
            }

            Section("Network") {
                Toggle("Allow LAN", isOn: $draft.allowLAN)
                Toggle("Enable TUN in runtime overlay", isOn: $draft.tunEnabled)
                Toggle("Close connections on policy change", isOn: $draft.closeConnectionsOnPolicyChange)
            }

            Section {
                HStack {
                    Button("Reset") {
                        draft = store.settings
                    }
                    .disabled(draft == store.settings)

                    Spacer()

                    Button("Save") {
                        Task { await store.saveSettings(draft) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft == store.settings)
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(minWidth: 560, minHeight: 440)
        .navigationTitle("Settings")
        .onAppear {
            draft = store.settings
        }
        .onReceive(store.$settings) { settings in
            if draft == AppSettings.default || draft == store.settings {
                draft = settings
            }
        }
    }

    private func chooseMihomoBinary() {
        let panel = NSOpenPanel()
        panel.title = "Choose mihomo Binary"
        panel.message = "Select the mihomo executable used to run the core."
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            draft.mihomoPath = url.path
        }
    }
}

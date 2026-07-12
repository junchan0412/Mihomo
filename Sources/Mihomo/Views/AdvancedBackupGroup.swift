import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedBackupGroup: View {
    @EnvironmentObject private var store: AppStore
    @Binding var draft: AppSettings
    @State private var secretBundlePassphrase = ""

    var body: some View {
        GroupBox("备份 / 同步") {
            VStack(alignment: .leading, spacing: 10) {
                backupCredentials
                secretChecklist
                backupActions
                manualSecretButton

                Divider()

                secretBundlePassphraseField
                secretBundleActions

                Text(store.backupStatus)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
    }

    private var backupCredentials: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("WebDAV URL")
                TextField("https://dav.example.com/Mihomo.zip", text: $draft.backupWebDAVURL)
            }
            GridRow {
                Text("WebDAV 用户")
                TextField("username", text: $draft.backupWebDAVUsername)
            }
            GridRow {
                Text("WebDAV 密码")
                SecureField("password", text: $draft.backupWebDAVPassword)
            }
            GridRow {
                Text("Gist Token")
                SecureField("token", text: $draft.gistToken)
            }
            GridRow {
                Text("Gist ID")
                TextField("可为空", text: $draft.gistID)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var secretChecklist: some View {
        HStack(spacing: 10) {
            ForEach(BackupSecretPolicy.secretChecklist(for: draft)) { item in
                Label {
                    Text("\(item.title) \(item.statusTitle)")
                } icon: {
                    Image(systemName: item.isPresent ? "checkmark.seal" : "exclamationmark.triangle")
                        .foregroundStyle(item.isPresent ? .green : .orange)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var backupActions: some View {
        HStack {
            Button {
                store.createLocalBackup()
            } label: {
                Label("本地备份", systemImage: "archivebox")
            }

            Button {
                restoreLocalBackup()
            } label: {
                Label("本地恢复", systemImage: "arrow.down.doc")
            }

            Button {
                Task {
                    await store.saveSettings(draft)
                    await store.uploadWebDAVBackup()
                }
            } label: {
                Label("上传 WebDAV", systemImage: "icloud.and.arrow.up")
            }

            Button {
                Task {
                    await store.saveSettings(draft)
                    await store.restoreWebDAVBackup()
                }
            } label: {
                Label("恢复 WebDAV", systemImage: "icloud.and.arrow.down")
            }

            Button {
                Task {
                    await store.saveSettings(draft)
                    await store.uploadGistBackup()
                }
            } label: {
                Label("同步 Gist", systemImage: "curlybraces")
            }

            Button {
                Task {
                    await store.saveSettings(draft)
                    await store.restoreGistBackup()
                }
            } label: {
                Label("恢复 Gist", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var manualSecretButton: some View {
        Button {
            store.applyManualSecrets(from: draft)
        } label: {
            Label("应用人工输入 Secret", systemImage: "key.fill")
        }
        .disabled(AppSecretValues(settings: draft).isEmpty)
    }

    private var secretBundlePassphraseField: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Secret Bundle 口令")
                SecureField("Passphrase", text: $secretBundlePassphrase)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var secretBundleActions: some View {
        HStack {
            Button {
                Task {
                    await store.saveSettings(draft)
                    exportSecretBundle()
                }
            } label: {
                Label("导出 Secret Bundle", systemImage: "key.viewfinder")
            }
            .disabled(trimmedPassphrase.isEmpty)

            Button {
                importSecretBundle()
            } label: {
                Label("导入 Secret Bundle", systemImage: "key.radiowaves.forward")
            }
            .disabled(trimmedPassphrase.isEmpty)
        }
    }

    private var trimmedPassphrase: String {
        secretBundlePassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restoreLocalBackup() {
        let panel = NSOpenPanel()
        panel.title = "选择备份文件"
        panel.allowedContentTypes = [.zipArchive]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.restoreLocalBackup(url: url) }
        }
    }

    private func exportSecretBundle() {
        let panel = NSSavePanel()
        panel.title = "导出 Secret Bundle"
        panel.nameFieldStringValue = "Mihomo-Secrets.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            store.exportPortableSecrets(to: url, passphrase: secretBundlePassphrase)
        }
    }

    private func importSecretBundle() {
        let panel = NSOpenPanel()
        panel.title = "导入 Secret Bundle"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.importPortableSecrets(from: url, passphrase: secretBundlePassphrase) }
        }
    }
}

private extension UTType {
    static let zipArchive = UTType(filenameExtension: "zip") ?? .data
}

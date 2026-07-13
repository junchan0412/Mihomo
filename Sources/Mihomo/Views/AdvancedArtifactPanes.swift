import SwiftUI

struct AdvancedProfileEncryptionGroup: View {
    @EnvironmentObject private var store: AppStore
    @Binding var draft: AppSettings

    var body: some View {
        GroupBox("Profile 加密") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("使用 Age 加密本地 Profile YAML", isOn: $draft.profileEncryptionEnabled)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Age 下载 URL")
                        TextField("age darwin arm64 tar.gz", text: $draft.ageDownloadURL)
                    }
                    GridRow {
                        Text("Age SHA-256")
                        TextField("必填；安装前校验下载包", text: $draft.ageDownloadSHA256)
                    }
                    GridRow {
                        Text("age")
                        TextField("age 可执行文件路径", text: $draft.ageBinaryPath)
                    }
                    GridRow {
                        Text("age-keygen")
                        TextField("age-keygen 可执行文件路径", text: $draft.ageKeygenPath)
                    }
                    GridRow {
                        Text("Identity")
                        TextField(AppPaths.ageIdentityFile.path, text: $draft.ageIdentityPath)
                    }
                    GridRow {
                        Text("Recipient")
                        TextField("age1...", text: $draft.ageRecipient)
                    }
                    GridRow {
                        Text("状态")
                        Text(store.ageStatus)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        Task {
                            await store.installAgeTools(
                                downloadURL: draft.ageDownloadURL,
                                expectedSHA256: draft.ageDownloadSHA256
                            )
                            draft = store.settings
                        }
                    } label: {
                        Label("安装 Age", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        Task {
                            await store.generateAgeIdentity(draftSettings: draft)
                            draft = store.settings
                        }
                    } label: {
                        Label("生成身份", systemImage: "key")
                    }

                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.migrateProfileEncryptionNow()
                        }
                    } label: {
                        Label(draft.profileEncryptionEnabled ? "加密现有 Profile" : "解密现有 Profile", systemImage: "lock.rotation")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct AdvancedConfigPreviewGroup: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GroupBox("配置预览 / Diff") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        store.refreshConfigArtifacts()
                    } label: {
                        Label("刷新预览", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Text("\(store.configPreview.split(separator: "\n").count) 行")
                        .foregroundStyle(.secondary)
                }

                HSplitView {
                    TextEditor(text: .constant(store.configPreview))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 260)
                    TextEditor(text: .constant(store.configDiff))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 260)
                }
                .frame(minHeight: 280)
            }
            .padding(.vertical, 4)
        }
    }
}

struct AdvancedGeoGroup: View {
    @EnvironmentObject private var store: AppStore
    @Binding var draft: AppSettings

    var body: some View {
        SettingsSection(
            title: "Geo 数据",
            subtitle: "默认维护 mihomo 常用的规则数据库与 IP 归属数据库；未手动填写 SHA-256 时自动读取上游 .sha256sum 校验。",
            systemImage: "globe.asia.australia"
        ) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("GeoIP.dat")
                    TextField("geoip.dat URL", text: $draft.geoIPURL)
                }
                GridRow {
                    Text("GeoSite.dat")
                    TextField("geosite.dat URL", text: $draft.geoSiteURL)
                }
                GridRow {
                    Text("Country.mmdb")
                    TextField("country.mmdb URL", text: $draft.countryMMDBURL)
                }
                GridRow {
                    Text("ASN.mmdb")
                    TextField("GeoLite2-ASN.mmdb URL", text: $draft.asnMMDBURL)
                }
                DisclosureGroup("手动 SHA-256（可选）") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("GeoIP")
                            TextField("留空时读取 .sha256sum", text: $draft.geoIPSHA256)
                        }
                        GridRow {
                            Text("GeoSite")
                            TextField("留空时读取 .sha256sum", text: $draft.geoSiteSHA256)
                        }
                        GridRow {
                            Text("Country")
                            TextField("留空时读取 .sha256sum", text: $draft.countryMMDBSHA256)
                        }
                        GridRow {
                            Text("ASN")
                            TextField("留空时读取 .sha256sum", text: $draft.asnMMDBSHA256)
                        }
                    }
                }
                GridRow {
                    Text("状态")
                    HStack {
                        Text(store.geoUpdateStatus)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task {
                                await store.saveSettings(draft)
                                await store.updateGeoData()
                            }
                        } label: {
                            Label("更新全部 Geo 数据", systemImage: "arrow.down.circle")
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(16)
        }
    }
}

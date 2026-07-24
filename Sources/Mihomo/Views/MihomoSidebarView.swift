import SwiftUI

struct MihomoSidebarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var activityStore: RuntimeActivityStore
    @Binding var selection: AppSection

    private let mainSections: [AppSection] = [.overview, .policies, .rules, .profiles, .overrides, .resources, .logs]
    private let engineSections: [AppSection] = [.networkSecurity, .advanced, .diagnostics]

    var body: some View {
        List(selection: $selection) {
            Section("常规") {
                sidebarRows(mainSections)
            }

            Section("引擎") {
                sidebarRows(engineSections)
            }

            Section("应用") {
                sidebarRows([.settings])
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(MihomoUI.pageBackground)
        .animation(reduceMotion ? nil : MihomoUI.Motion.soft, value: selection)
        .safeAreaInset(edge: .top, spacing: 0) {
            brandHeader
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    @ViewBuilder
    private func sidebarRows(_ sections: [AppSection]) -> some View {
        ForEach(sections) { section in
            Label(section.sidebarTitle, systemImage: section.systemImage)
                .tag(section)
                .help(section.title)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mihomo")
                    .font(.headline)
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MihomoUI.pageBackground)
        .accessibilityElement(children: .combine)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 9) {
            Button {
                openWindow(id: "connections")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(Color.accentColor)
                    Text("连接")
                        .font(MihomoUI.Fonts.bodyMedium)
                    Spacer()
                    Text("\(activityStore.connections.count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MihomoUI.cardStroke, lineWidth: 1)
            }
            .help("在独立窗口中显示连接")
            .accessibilityIdentifier("sidebar.connections")

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                sidebarStatus("系统代理", isOn: store.systemProxyEnabled, activeColor: .green)
                sidebarStatus("TUN", isOn: store.settings.tunEnabled, activeColor: .purple)
                sidebarStatus("核心", isOn: store.isCoreRunning, activeColor: .red)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MihomoUI.pageBackground)
    }

    private func sidebarStatus(_ title: String, isOn: Bool, activeColor: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? activeColor : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
            Text(title)
            Spacer()
            Text(isOn ? "开" : "关")
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "已启用" : "未启用")
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
    }
}

private extension AppSection {
    var sidebarTitle: String {
        switch self {
        case .activity: return "连接"
        case .networkSecurity: return "网络"
        case .advanced: return "高级工具"
        case .diagnostics: return "诊断"
        default: return title
        }
    }
}

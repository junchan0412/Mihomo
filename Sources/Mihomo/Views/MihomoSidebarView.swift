import SwiftUI

struct MihomoSidebarView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: AppSection

    private let mainSections: [AppSection] = [.overview, .activity, .policies, .rules, .profiles, .overrides, .resources, .logs]
    private let engineSections: [AppSection] = [.networkSecurity, .advanced, .diagnostics]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sidebarGroup(title: "常规", sections: mainSections)
                    sidebarGroup(title: "引擎", sections: engineSections)
                    sidebarGroup(title: "应用", sections: [.settings])
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
            }

            statusFooter
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.bar)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mihomo")
                    .font(.system(size: 13, weight: .semibold))
                Text(appVersion)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
    }

    private func sidebarGroup(title: String? = nil, sections: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
            }

            ForEach(sections) { section in
                SidebarSectionButton(
                    section: section,
                    isSelected: selection == section
                ) {
                    selection = section
                }
            }
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            sidebarStatus("系统代理", isOn: store.systemProxyEnabled, activeColor: .green)
            sidebarStatus("TUN", isOn: store.settings.tunEnabled, activeColor: .purple)
            sidebarStatus("核心", isOn: store.isCoreRunning, activeColor: .red)
        }
        .font(MihomoUI.Fonts.caption)
        .foregroundStyle(.secondary)
    }

    private func sidebarStatus(_ title: String, isOn: Bool, activeColor: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? activeColor : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
            Text(title)
        }
    }
}

private struct SidebarSectionButton: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18)
                Text(section.sidebarTitle)
                    .font(MihomoUI.Fonts.sidebar)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(section.title)
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

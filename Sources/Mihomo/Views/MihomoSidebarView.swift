import SwiftUI

struct MihomoSidebarView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: AppSection

    private let mainSections: [AppSection] = [.overview, .activity, .policies, .rules, .profiles, .logs]
    private let engineSections: [AppSection] = [.settings, .networkSecurity, .resources, .advanced, .diagnostics]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarGroup(sections: mainSections)
                    sidebarGroup(title: "引擎", sections: engineSections)
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }

            statusFooter
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.14))
                Text("M")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mihomo")
                    .font(.headline.weight(.bold))
                Text(appVersion)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
    }

    private func sidebarGroup(title: String? = nil, sections: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
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
        VStack(alignment: .leading, spacing: 6) {
            sidebarStatus("系统代理", isOn: store.systemProxyEnabled, activeColor: .green)
            sidebarStatus("TUN", isOn: store.settings.tunEnabled, activeColor: .purple)
            sidebarStatus("核心", isOn: store.isCoreRunning, activeColor: .red)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func sidebarStatus(_ title: String, isOn: Bool, activeColor: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? activeColor : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
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
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 22)
                Text(section.sidebarTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
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
        case .settings: return "通用"
        case .advanced: return "DNS"
        case .diagnostics: return "嗅探"
        default: return title
        }
    }
}

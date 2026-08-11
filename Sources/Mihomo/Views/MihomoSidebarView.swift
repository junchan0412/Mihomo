import SwiftUI

struct MihomoSidebarView: View {
    @Binding var selection: AppSection
    @AppStorage("sidebar.favorites") private var favoriteSectionValues = ""
    @AppStorage("sidebar.section.general.expanded") private var mainSectionsExpanded = true
    @AppStorage("sidebar.section.engine.expanded") private var engineSectionsExpanded = true
    @AppStorage("sidebar.section.application.expanded") private var applicationSectionsExpanded = true

    private let mainSections: [AppSection] = [.overview, .policies, .rules, .profiles, .overrides, .resources, .logs]
    private let engineSections: [AppSection] = [.networkSecurity, .advanced, .diagnostics]

    var body: some View {
        VStack(spacing: 0) {
            brandHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if favoriteSections.isEmpty == false {
                        sidebarSectionTitle("收藏")
                        sidebarRows(favoriteSections)
                    }

                    collapsibleSection(
                        title: "常规",
                        isExpanded: $mainSectionsExpanded,
                        sections: mainSections
                    )
                    collapsibleSection(
                        title: "引擎",
                        isExpanded: $engineSectionsExpanded,
                        sections: engineSections
                    )
                    collapsibleSection(
                        title: "应用",
                        isExpanded: $applicationSectionsExpanded,
                        sections: [.settings]
                    )
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: .infinity)

            MihomoSidebarFooter()
        }
        .background(MihomoUI.sidebarBackground)
    }

    private func collapsibleSection(
        title: String,
        isExpanded: Binding<Bool>,
        sections: [AppSection]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withTransaction(Transaction(animation: nil)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .frame(width: 10)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                sidebarRows(sections)
            }
        }
        .transaction { $0.animation = nil }
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarRows(_ sections: [AppSection]) -> some View {
        VStack(spacing: 2) {
            ForEach(sections) { section in
                sidebarRow(section)
            }
        }
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        let isSelected = selection == section
        return Button {
            guard selection != section else { return }
            withTransaction(Transaction(animation: nil)) {
                selection = section
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 20, height: 20)
                Text(section.sidebarTitle)
                    .font(MihomoUI.Fonts.sidebar)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .transaction { $0.animation = nil }
        .help(section.title)
        .accessibilityLabel(section.sidebarTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(favoriteSections.contains(section) ? "从收藏移除" : "添加到收藏") {
                toggleFavorite(section)
            }
        }
    }

    private var favoriteSections: [AppSection] {
        favoriteSectionValues
            .split(separator: ",")
            .compactMap { AppSection(rawValue: String($0)) }
    }

    private func toggleFavorite(_ section: AppSection) {
        var values = favoriteSections
        if let index = values.firstIndex(of: section) {
            values.remove(at: index)
        } else {
            values.append(section)
        }
        favoriteSectionValues = values.map(\.rawValue).joined(separator: ",")
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
        .background(MihomoUI.sidebarBackground)
        .accessibilityElement(children: .combine)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
    }
}

private struct MihomoSidebarFooter: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var activityStore: RuntimeActivityStore

    var body: some View {
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
        .background(MihomoUI.sidebarBackground)
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

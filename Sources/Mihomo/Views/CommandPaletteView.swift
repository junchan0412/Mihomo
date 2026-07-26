import SwiftUI

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var commands: [CommandPaletteCommand] {
        let navigation = AppSection.sidebarSections.map { section in
            CommandPaletteCommand(
                title: "打开 \(section.title)",
                detail: "导航",
                systemImage: section.systemImage,
                keywords: [section.rawValue, section.title],
                action: { store.selectedSection = section }
            )
        }
        let profiles = store.profiles.map { profile in
            CommandPaletteCommand(
                title: "切换配置：\(profile.name)",
                detail: profile.id == store.settings.activeProfileID ? "当前配置" : "配置",
                systemImage: profile.id == store.settings.activeProfileID ? "checkmark.circle.fill" : "doc.text",
                keywords: [profile.name, "配置", "切换"],
                action: { Task { await store.setActiveProfile(profile) } }
            )
        }
        return navigation + [
            CommandPaletteCommand(
                title: store.isCoreRunning ? "停止核心" : "启动核心",
                detail: "网络控制",
                systemImage: store.isCoreRunning ? "stop.fill" : "play.fill",
                keywords: ["核心", "启动", "停止"],
                action: { Task { await store.toggleCore() } }
            ),
            CommandPaletteCommand(
                title: store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理",
                detail: "网络控制",
                systemImage: "network",
                keywords: ["代理", "系统", "网络"],
                action: { Task { await store.toggleSystemProxy() } }
            ),
            CommandPaletteCommand(
                title: store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN",
                detail: "网络控制",
                systemImage: "lock.shield",
                keywords: ["tun", "路由", "网络"],
                action: { Task { await store.setTunEnabled(!store.settings.tunEnabled) } }
            ),
            CommandPaletteCommand(
                title: "测试全部节点延迟",
                detail: "策略",
                systemImage: "speedometer",
                keywords: ["测速", "延迟", "策略"],
                action: { Task { await store.testAllProxyDelays() } }
            ),
            CommandPaletteCommand(
                title: "刷新全部资源",
                detail: "资源",
                systemImage: "arrow.clockwise",
                keywords: ["刷新", "更新", "资源", "provider"],
                action: { Task { await store.updateAllExternalResources() } }
            ),
            CommandPaletteCommand(
                title: "运行诊断",
                detail: "诊断",
                systemImage: "stethoscope",
                keywords: ["诊断", "健康", "网络"],
                action: { Task { await store.runDiagnostics() } }
            )
        ] + profiles
    }

    private var filteredCommands: [CommandPaletteCommand] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return commands }
        return commands.filter { command in
            ([command.title, command.detail] + command.keywords)
                .contains { $0.localizedCaseInsensitiveContains(normalized) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索命令、页面或配置", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .padding(14)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCommands) { command in
                        Button {
                            dismiss()
                            command.action()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: command.systemImage)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 18)
                                Text(command.title)
                                    .lineLimit(1)
                                Spacer()
                                Text(command.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if command.id != filteredCommands.last?.id { Divider().padding(.leading, 42) }
                    }
                }
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 560)
        .onAppear { isSearchFocused = true }
    }
}

private struct CommandPaletteCommand: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var systemImage: String
    var keywords: [String]
    var action: () -> Void
}

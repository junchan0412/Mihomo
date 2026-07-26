import SwiftUI

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var selectedCommandID: String?
    @FocusState private var isSearchFocused: Bool

    private var commands: [CommandPaletteCommand] {
        let navigation = AppSection.sidebarSections.map { section in
            CommandPaletteCommand(
                id: "navigate-\(section.rawValue)",
                title: "打开 \(section.title)",
                detail: "导航",
                systemImage: section.systemImage,
                keywords: [section.rawValue, section.title],
                action: { store.selectedSection = section }
            )
        }
        let profiles = store.profiles.map { profile in
            CommandPaletteCommand(
                id: "profile-\(profile.id.uuidString)",
                title: "切换配置：\(profile.name)",
                detail: profile.id == store.settings.activeProfileID ? "当前配置" : "配置",
                systemImage: profile.id == store.settings.activeProfileID ? "checkmark.circle.fill" : "doc.text",
                keywords: [profile.name, "配置", "切换"],
                action: { Task { await store.setActiveProfile(profile) } }
            )
        }
        return navigation + [
            CommandPaletteCommand(
                id: "core",
                title: store.isCoreRunning ? "停止核心" : "启动核心",
                detail: "网络控制",
                systemImage: store.isCoreRunning ? "stop.fill" : "play.fill",
                keywords: ["核心", "启动", "停止"],
                action: { Task { await store.toggleCore() } }
            ),
            CommandPaletteCommand(
                id: "system-proxy",
                title: store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理",
                detail: "网络控制",
                systemImage: "network",
                keywords: ["代理", "系统", "网络"],
                action: { Task { await store.toggleSystemProxy() } }
            ),
            CommandPaletteCommand(
                id: "tun",
                title: store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN",
                detail: "网络控制",
                systemImage: "lock.shield",
                keywords: ["tun", "路由", "网络"],
                action: { Task { await store.setTunEnabled(!store.settings.tunEnabled) } }
            ),
            CommandPaletteCommand(
                id: "test-delays",
                title: "测试全部节点延迟",
                detail: "策略",
                systemImage: "speedometer",
                keywords: ["测速", "延迟", "策略"],
                action: { Task { await store.testAllProxyDelays() } }
            ),
            CommandPaletteCommand(
                id: "refresh-resources",
                title: "刷新全部资源",
                detail: "资源",
                systemImage: "arrow.clockwise",
                keywords: ["刷新", "更新", "资源", "provider"],
                action: { Task { await store.updateAllExternalResources() } }
            ),
            CommandPaletteCommand(
                id: "run-diagnostics",
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
                .onSubmit(activateSelectedCommand)
                .onKeyPress(.upArrow) {
                    moveSelection(.up)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(.down)
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
                .padding(14)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCommands) { command in
                        Button {
                            activate(command)
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
                            .background(
                                selectedCommandID == command.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovering in
                            if isHovering { selectedCommandID = command.id }
                        }
                        if command.id != filteredCommands.last?.id { Divider().padding(.leading, 42) }
                    }
                }
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 560)
        .onAppear {
            isSearchFocused = true
            selectedCommandID = filteredCommands.first?.id
        }
        .onChange(of: query) {
            selectedCommandID = filteredCommands.first?.id
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard filteredCommands.isEmpty == false else { return }
        let currentIndex = filteredCommands.firstIndex { $0.id == selectedCommandID } ?? 0
        let nextIndex: Int
        switch direction {
        case .up: nextIndex = max(0, currentIndex - 1)
        case .down: nextIndex = min(filteredCommands.count - 1, currentIndex + 1)
        default: return
        }
        selectedCommandID = filteredCommands[nextIndex].id
    }

    private func activateSelectedCommand() {
        guard let selected = filteredCommands.first(where: { $0.id == selectedCommandID }) ?? filteredCommands.first else { return }
        activate(selected)
    }

    private func activate(_ command: CommandPaletteCommand) {
        dismiss()
        command.action()
    }
}

private struct CommandPaletteCommand: Identifiable {
    let id: String
    var title: String
    var detail: String
    var systemImage: String
    var keywords: [String]
    var action: () -> Void
}

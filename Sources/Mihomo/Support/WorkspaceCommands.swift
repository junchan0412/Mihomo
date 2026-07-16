import AppKit
import SwiftUI

@MainActor
struct WorkspaceCommandContext {
    var search: (() -> Void)?
    var refresh: (() -> Void)?
    var activateSelection: (() -> Void)?
    var previewSelection: (() -> Void)?
    var deleteSelection: (() -> Void)?
    var collapseSelection: (() -> Void)?
    var expandSelection: (() -> Void)?
}

private struct WorkspaceCommandContextKey: FocusedValueKey {
    typealias Value = WorkspaceCommandContext
}

extension FocusedValues {
    var workspaceCommands: WorkspaceCommandContext? {
        get { self[WorkspaceCommandContextKey.self] }
        set { self[WorkspaceCommandContextKey.self] = newValue }
    }
}

private struct CompatibleSearchFocusModifier: ViewModifier {
    let focus: FocusState<Bool>.Binding

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused(focus)
        } else {
            content
        }
    }
}

extension View {
    func compatibleSearchFocused(_ focus: FocusState<Bool>.Binding) -> some View {
        modifier(CompatibleSearchFocusModifier(focus: focus))
    }
}

enum MihomoSearchFocus {
    static func request() {
        DispatchQueue.main.async {
            guard let root = NSApp.keyWindow?.contentView?.superview,
                  let searchField = findSearchField(in: root)
            else { return }
            searchField.window?.makeFirstResponder(searchField)
        }
    }

    private static func findSearchField(in view: NSView) -> NSSearchField? {
        if let searchField = view as? NSSearchField {
            return searchField
        }
        for subview in view.subviews {
            if let searchField = findSearchField(in: subview) {
                return searchField
            }
        }
        return nil
    }
}

struct MihomoCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AppStore
    @FocusedValue(\.workspaceCommands) private var workspaceCommands

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                navigate(to: .settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("查找...") {
                workspaceCommands?.search?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(workspaceCommands?.search == nil)

            Button("打开所选项目") {
                workspaceCommands?.activateSelection?()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(workspaceCommands?.activateSelection == nil)

            Button("快速查看所选项目") {
                workspaceCommands?.previewSelection?()
            }
            .keyboardShortcut(KeyEquivalent(" "), modifiers: [])
            .disabled(workspaceCommands?.previewSelection == nil)

            Button("删除所选项目") {
                workspaceCommands?.deleteSelection?()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(workspaceCommands?.deleteSelection == nil)
        }

        CommandMenu("导航") {
            navigationButton(.overview, key: "1")
            navigationButton(.activity, key: "2")
            navigationButton(.policies, key: "3")
            navigationButton(.rules, key: "4")
            navigationButton(.profiles, key: "5")
            navigationButton(.overrides, key: "6")
            navigationButton(.resources, key: "7")
            navigationButton(.networkSecurity, key: "8")
            navigationButton(.diagnostics, key: "9")

            Divider()

            Button("收起所选项目") {
                workspaceCommands?.collapseSelection?()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(workspaceCommands?.collapseSelection == nil)

            Button("展开所选项目") {
                workspaceCommands?.expandSelection?()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(workspaceCommands?.expandSelection == nil)
        }

        CommandMenu("控制") {
            Button("显示主窗口") {
                store.isLightweightModeActive = false
                MainWindowPresenter.present(openWindow: openWindow)
            }
            .keyboardShortcut("m", modifiers: .command)

            Divider()

            Button(store.isCoreRunning ? "停止核心" : "启动核心") {
                Task { await store.toggleCore() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("重启核心") {
                Task { await store.restartCore() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(store.isCoreRunning == false)

            Divider()

            Button(store.isLightweightModeActive ? "退出轻量模式" : "进入轻量模式") {
                if store.isLightweightModeActive {
                    store.isLightweightModeActive = false
                    MainWindowPresenter.present(openWindow: openWindow)
                } else {
                    store.enterLightweightMode()
                }
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
        }

        CommandMenu("网络") {
            modeToggle("规则模式", mode: "rule")
            modeToggle("全局模式", mode: "global")
            modeToggle("直连模式", mode: "direct")

            Divider()

            Button(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理") {
                Task { await store.toggleSystemProxy() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!store.isCoreRunning && !store.systemProxyEnabled)

            Button(store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN") {
                Task { await store.setTunEnabled(!store.settings.tunEnabled) }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Button(store.settings.autoSetSystemDNS ? "关闭系统 DNS 接管" : "开启系统 DNS 接管") {
                var updated = store.settings
                updated.autoSetSystemDNS.toggle()
                Task { await store.saveSettings(updated) }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }

        CommandMenu("维护") {
            Button("刷新当前页面") {
                workspaceCommands?.refresh?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(workspaceCommands?.refresh == nil)

            Button("刷新核心状态") {
                Task { await store.refreshController() }
            }
            .keyboardShortcut("r", modifiers: [.command, .control])

            Button("刷新所有订阅") {
                Task { await store.refreshAllRemoteSubscriptions() }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button("测试全部节点延迟") {
                Task { await store.testAllProxyDelays() }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("运行诊断") {
                Task { await store.runDiagnostics() }
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("导出诊断包") {
                store.exportDiagnosticBundle()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])

            Divider()

            Button("检查更新...") {
                openWindow(id: "software-update")
                Task { await store.checkForSoftwareUpdate() }
            }
            .keyboardShortcut("u", modifiers: [.command, .option])

            if let update = store.availableUpdate {
                Button("安装更新 \(update.version)") {
                    Task { await store.installSoftwareUpdate() }
                }
            }
        }
    }

    @ViewBuilder
    private func navigationButton(_ section: AppSection, key: KeyEquivalent) -> some View {
        Button(section.title) {
            navigate(to: section)
        }
        .keyboardShortcut(key, modifiers: .command)
    }

    private func navigate(to section: AppSection) {
        store.selectedSection = section
        store.isLightweightModeActive = false
        MainWindowPresenter.present(openWindow: openWindow)
    }

    @ViewBuilder
    private func modeToggle(_ title: String, mode: String) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { store.currentMode == mode },
                set: { enabled in
                    guard enabled else { return }
                    Task { await store.setMode(mode) }
                }
            )
        )
        .disabled(store.isCoreRunning == false)
    }
}

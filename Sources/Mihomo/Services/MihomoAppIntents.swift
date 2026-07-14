import AppIntents
import Foundation

enum MihomoIntentAction: Equatable {
    case showMainWindow
    case setCoreRunning(Bool)
    case toggleSystemProxy
    case setMode(String)
    case refreshSubscriptions
    case runDiagnostics
}

@MainActor
final class AppIntentRouter: ObservableObject {
    static let shared = AppIntentRouter()

    @Published var pendingAction: MihomoIntentAction?

    private init() {}

    func enqueue(_ action: MihomoIntentAction) {
        pendingAction = action
    }
}

enum RoutingModeIntentValue: String, AppEnum {
    case rule
    case global
    case direct

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "路由模式"

    static var caseDisplayRepresentations: [RoutingModeIntentValue: DisplayRepresentation] = [
        .rule: "规则",
        .global: "全局",
        .direct: "直连"
    ]
}

struct ShowMihomoIntent: AppIntent {
    static var title: LocalizedStringResource = "显示 Mihomo"
    static var description = IntentDescription("打开 Mihomo 主窗口。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.enqueue(.showMainWindow)
        return .result()
    }
}

struct StartMihomoCoreIntent: AppIntent {
    static var title: LocalizedStringResource = "启动 Mihomo 核心"
    static var description = IntentDescription("启动当前配置使用的 Mihomo 核心。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.enqueue(.setCoreRunning(true))
        return .result()
    }
}

struct StopMihomoCoreIntent: AppIntent {
    static var title: LocalizedStringResource = "停止 Mihomo 核心"
    static var description = IntentDescription("停止正在运行的 Mihomo 核心。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.enqueue(.setCoreRunning(false))
        return .result()
    }
}

struct ToggleSystemProxyIntent: AppIntent {
    static var title: LocalizedStringResource = "切换系统代理"
    static var description = IntentDescription("切换 Mihomo 的系统代理接管状态。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.enqueue(.toggleSystemProxy)
        return .result()
    }
}

struct SetRoutingModeIntent: AppIntent {
    static var title: LocalizedStringResource = "设置 Mihomo 路由模式"
    static var description = IntentDescription("切换规则、全局或直连模式。")
    static var openAppWhenRun = true

    @Parameter(title: "模式")
    var mode: RoutingModeIntentValue

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.enqueue(.setMode(mode.rawValue))
        return .result()
    }
}

struct RefreshSubscriptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新 Mihomo 订阅"
    static var description = IntentDescription("刷新所有远程配置订阅。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.enqueue(.refreshSubscriptions)
        return .result()
    }
}

struct RunMihomoDiagnosticsIntent: AppIntent {
    static var title: LocalizedStringResource = "运行 Mihomo 诊断"
    static var description = IntentDescription("运行诊断并打开诊断工作区。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.enqueue(.runDiagnostics)
        return .result()
    }
}

struct MihomoAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
                intent: ShowMihomoIntent(),
                phrases: ["显示 \(.applicationName)", "打开 \(.applicationName)"],
                shortTitle: "显示 Mihomo",
                systemImageName: "network"
            )
        AppShortcut(
                intent: StartMihomoCoreIntent(),
                phrases: ["启动 \(.applicationName) 核心"],
                shortTitle: "启动核心",
                systemImageName: "play.fill"
            )
        AppShortcut(
                intent: StopMihomoCoreIntent(),
                phrases: ["停止 \(.applicationName) 核心"],
                shortTitle: "停止核心",
                systemImageName: "stop.fill"
            )
        AppShortcut(
                intent: ToggleSystemProxyIntent(),
                phrases: ["切换 \(.applicationName) 系统代理"],
                shortTitle: "切换系统代理",
                systemImageName: "network"
            )
        AppShortcut(
                intent: SetRoutingModeIntent(),
                phrases: ["设置 \(.applicationName) 路由模式"],
                shortTitle: "设置路由模式",
                systemImageName: "switch.2"
            )
        AppShortcut(
                intent: RefreshSubscriptionsIntent(),
                phrases: ["刷新 \(.applicationName) 订阅"],
                shortTitle: "刷新订阅",
                systemImageName: "arrow.triangle.2.circlepath"
            )
        AppShortcut(
                intent: RunMihomoDiagnosticsIntent(),
                phrases: ["运行 \(.applicationName) 诊断"],
                shortTitle: "运行诊断",
                systemImageName: "stethoscope"
            )
    }
}

extension AppStore {
    func handleAppIntent(_ action: MihomoIntentAction) async {
        switch action {
        case .showMainWindow:
            isLightweightModeActive = false
        case let .setCoreRunning(shouldRun):
            if shouldRun, isCoreRunning == false {
                await startCore()
            } else if shouldRun == false, isCoreRunning {
                await stopCore()
            }
        case .toggleSystemProxy:
            await toggleSystemProxy()
        case let .setMode(mode):
            await setMode(mode)
        case .refreshSubscriptions:
            await refreshAllRemoteSubscriptions()
        case .runDiagnostics:
            selectedSection = .diagnostics
            await runDiagnostics()
        }
    }
}

import Foundation
import ServiceManagement

final class LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "已启用登录项"
        case .notRegistered:
            return "未注册登录项"
        case .requiresApproval:
            return "需要在系统设置中批准登录项"
        case .notFound:
            return "当前 App Bundle 不支持注册登录项"
        @unknown default:
            return "未知登录项状态"
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}

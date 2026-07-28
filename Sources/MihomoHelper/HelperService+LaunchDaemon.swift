import Foundation

extension HelperService {
    func installCoreLaunchDaemon(
        corePath: NSString,
        configPath: NSString,
        workDirectory: NSString,
        logPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        do {
            let paths = try validatedCorePaths(
                mihomoPath: corePath as String,
                configPath: configPath as String,
                workDirectory: workDirectory as String,
                logPath: logPath as String
            )
            _ = try coreRuntime.validate(
                mihomoPath: paths.mihomoPath,
                configPath: paths.configPath,
                workDirectory: paths.workDirectory
            )
            let path = try coreLaunchDaemonTool.install(
                corePath: paths.mihomoPath,
                configPath: paths.configPath,
                workDirectory: paths.workDirectory,
                logPath: try requiredLogPath(paths)
            )
            reply(HelperReply.ok("Core LaunchDaemon 已安装并加载", payload: ["path": path]))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func uninstallCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void) {
        do {
            try coreLaunchDaemonTool.uninstall()
            reply(HelperReply.ok("Core LaunchDaemon 已卸载"))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func startCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void) {
        do {
            try coreLaunchDaemonTool.start()
            reply(HelperReply.ok("Core LaunchDaemon 已启动"))
        } catch {
            reply(HelperReply.error(error))
        }
    }

    func stopCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void) {
        do {
            try coreLaunchDaemonTool.stop()
            reply(HelperReply.ok("Core LaunchDaemon 已停止"))
        } catch {
            reply(HelperReply.error(error))
        }
    }
}

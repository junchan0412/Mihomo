import Foundation

public enum HelperCorePathScope {
    public static func allowedExecutablePaths(
        userHomeDirectory: URL,
        appBundleURL: URL?,
        additionalPath: String? = nil
    ) -> Set<String> {
        var paths: Set<String> = [
            userHomeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent(HelperPathPolicy.supportDirectoryName, isDirectory: true)
                .appendingPathComponent(HelperPathPolicy.coreDirectoryName, isDirectory: true)
                .appendingPathComponent("mihomo")
                .standardizedFileURL
                .path
        ]
        if let appBundleURL {
            paths.insert(
                appBundleURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(HelperPathPolicy.coreDirectoryName, isDirectory: true)
                    .appendingPathComponent("mihomo")
                    .standardizedFileURL
                    .path
            )
        }
        if let additionalPath, additionalPath.isEmpty == false {
            paths.insert(URL(fileURLWithPath: additionalPath).standardizedFileURL.path)
        }
        return paths
    }
}

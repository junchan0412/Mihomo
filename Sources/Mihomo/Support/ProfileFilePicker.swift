import AppKit
import UniformTypeIdentifiers

enum ProfileFilePicker {
    static func localProfile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func storageDirectory(current: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择配置存储路径"
        panel.message = "选择用于保存配置 YAML 文件的目录。现有配置会复制到新目录。"
        panel.prompt = "使用此目录"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = current
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private extension UTType {
    static let yaml = UTType(filenameExtension: "yaml") ?? .text
}

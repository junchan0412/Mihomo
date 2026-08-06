import Foundation

struct NodeProviderProfileSynchronizer {
    typealias YAMLMap = [String: Any]

    func synchronizationPreview(
        _ nodeProviders: [NodeProvider],
        into profileContent: String,
        profileID: UUID,
        profileName: String,
        removingProviderNames: Set<String> = []
    ) throws -> NodeProviderProfileSynchronization {
        var lines = lines(from: profileContent)
        var changes: [NodeProviderProfileChange] = []
        let selected = nodeProviders.filter(\.enabled)
        let normalizedRemovalNames = Set(removingProviderNames.map(normalizedName))

        if normalizedRemovalNames.isEmpty == false,
           let section = try proxyProviderSection(in: lines) {
            let blocks = providerBlocks(in: lines, section: section)
                .filter { normalizedRemovalNames.contains(normalizedName($0.name)) }
            for block in blocks.reversed() {
                lines.removeSubrange(block.start..<block.end)
            }
            changes.append(contentsOf: blocks.map {
                NodeProviderProfileChange(
                    profileID: profileID,
                    profileName: profileName,
                    providerName: $0.name,
                    kind: .remove,
                    fields: ["proxy-providers"]
                )
            })
        }

        guard selected.isEmpty == false else {
            let content = content(from: lines, preservingTrailingNewlineFrom: profileContent)
            return NodeProviderProfileSynchronization(content: content, changes: changes)
        }

        if try proxyProviderSection(in: lines) == nil {
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append("proxy-providers:")
        }

        for provider in selected {
            let name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else { continue }
            guard let section = try proxyProviderSection(in: lines) else { continue }
            let blocks = providerBlocks(in: lines, section: section)
            if let block = blocks.first(where: { normalizedName($0.name) == provider.normalizedName }) {
                let current = definition(in: lines, block: block)
                let fields = provider.definition.differs(from: current)
                guard fields.isEmpty == false else { continue }
                update(provider.definition, in: &lines, block: block)
                changes.append(NodeProviderProfileChange(
                    profileID: profileID,
                    profileName: profileName,
                    providerName: name,
                    kind: .update,
                    fields: fields
                ))
            } else {
                append(provider, to: &lines, section: section)
                changes.append(NodeProviderProfileChange(
                    profileID: profileID,
                    profileName: profileName,
                    providerName: name,
                    kind: .add,
                    fields: ["类型", "URL", "路径", "更新间隔"]
                ))
            }
        }

        let content = content(from: lines, preservingTrailingNewlineFrom: profileContent)
        return NodeProviderProfileSynchronization(content: content, changes: changes)
    }

    func synchronizing(
        _ nodeProviders: [NodeProvider],
        into profileContent: String,
        removingProviderNames: Set<String>
    ) throws -> String {
        try synchronizationPreview(
            nodeProviders,
            into: profileContent,
            profileID: UUID(),
            profileName: "当前配置",
            removingProviderNames: removingProviderNames
        ).content
    }

    func synchronizing(_ nodeProviders: [NodeProvider], into profileContent: String) throws -> String {
        try synchronizing(nodeProviders, into: profileContent, removingProviderNames: [])
    }

    func preservingExistingProviders(from previousContent: String, in refreshedContent: String) throws -> String {
        try preservingExistingProvidersPreview(from: previousContent, in: refreshedContent).content
    }

    func preservingExistingProvidersPreview(from previousContent: String, in refreshedContent: String) throws -> NodeProviderPreservationResult {
        var refreshedLines = lines(from: refreshedContent)
        let previousLines = lines(from: previousContent)
        guard let previousSection = try proxyProviderSection(in: previousLines) else {
            return NodeProviderPreservationResult(content: refreshedContent, preservedProviderNames: [])
        }
        let previousBlocks = providerBlocks(in: previousLines, section: previousSection)
        guard previousBlocks.isEmpty == false else {
            return NodeProviderPreservationResult(content: refreshedContent, preservedProviderNames: [])
        }

        var preservedNames: [String] = []

        if let refreshedSection = try proxyProviderSection(in: refreshedLines) {
            let incoming = Set(providerBlocks(in: refreshedLines, section: refreshedSection).map { normalizedName($0.name) })
            let missing = previousBlocks.filter { incoming.contains(normalizedName($0.name)) == false }
            guard missing.isEmpty == false else {
                return NodeProviderPreservationResult(content: refreshedContent, preservedProviderNames: [])
            }

            var insertionIndex = refreshedSection.end
            for block in missing {
                let blockLines = Array(previousLines[block.start..<block.end])
                refreshedLines.insert(contentsOf: blockLines, at: insertionIndex)
                insertionIndex += blockLines.count
            }
            preservedNames = missing.map(\.name)
        } else {
            if refreshedLines.last?.isEmpty == false { refreshedLines.append("") }
            refreshedLines.append(contentsOf: previousLines[previousSection.start..<previousSection.end])
            preservedNames = previousBlocks.map(\.name)
        }

        return NodeProviderPreservationResult(
            content: content(from: refreshedLines, preservingTrailingNewlineFrom: refreshedContent),
            preservedProviderNames: preservedNames
        )
    }

    func definition(for providerName: String, in profileContent: String) throws -> NodeProviderDefinition? {
        let profileLines = lines(from: profileContent)
        guard let section = try proxyProviderSection(in: profileLines) else { return nil }
        return providerBlocks(in: profileLines, section: section)
            .first { normalizedName($0.name) == normalizedName(providerName) }
            .map { definition(in: profileLines, block: $0) }
    }

    private func lines(from content: String) -> [String] {
        var result = content.components(separatedBy: "\n")
        if content.hasSuffix("\n"), result.last == "" {
            result.removeLast()
        }
        return result
    }

    private func content(from lines: [String], preservingTrailingNewlineFrom original: String) -> String {
        let text = lines.joined(separator: "\n")
        return original.hasSuffix("\n") ? text + "\n" : text
    }

    private func proxyProviderSection(in lines: [String]) throws -> YAMLSection? {
        for index in lines.indices where topLevelKey(in: lines[index]) == "proxy-providers" {
            let line = lines[index]
            guard let colon = line.firstIndex(of: ":") else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard value.isEmpty || value.hasPrefix("#") else {
                throw syncError("暂不支持内联 proxy-providers；请改用标准缩进映射后重试。")
            }
            var end = lines.count
            for candidate in (index + 1)..<lines.count where topLevelKey(in: lines[candidate]) != nil {
                end = candidate
                break
            }
            return YAMLSection(start: index, end: end)
        }
        return nil
    }

    private func providerBlocks(in lines: [String], section: YAMLSection) -> [YAMLProviderBlock] {
        let candidates = (section.start + 1..<section.end).compactMap { index -> (Int, String)? in
            guard let name = mappingKey(in: lines[index]), indentation(of: lines[index]) > 0 else { return nil }
            return (index, name)
        }
        guard let providerIndent = candidates.map(\.0).map({ indentation(of: lines[$0]) }).min() else { return [] }
        let headers = candidates.filter { indentation(of: lines[$0.0]) == providerIndent }
        return headers.enumerated().map { offset, header in
            YAMLProviderBlock(
                name: header.1,
                start: header.0,
                end: offset + 1 < headers.count ? headers[offset + 1].0 : section.end,
                indent: providerIndent
            )
        }
    }

    private func definition(in lines: [String], block: YAMLProviderBlock) -> NodeProviderDefinition {
        let childIndent = block.indent + 2
        func value(_ key: String) -> String? {
            for index in (block.start + 1)..<block.end {
                guard indentation(of: lines[index]) == childIndent,
                      mappingKey(in: lines[index]) == key
                else { continue }
                return scalarValue(in: lines[index])
            }
            return nil
        }
        return NodeProviderDefinition(
            providerType: value("type") ?? "http",
            url: value("url") ?? "",
            path: value("path") ?? "",
            interval: Int(value("interval") ?? "") ?? 86_400
        )
    }

    private func update(_ definition: NodeProviderDefinition, in lines: inout [String], block: YAMLProviderBlock) {
        var end = block.end
        let childIndent = block.indent + 2
        let values: [(String, String?)] = [
            ("type", definition.normalizedType),
            ("url", definition.normalizedURL.isEmpty ? nil : definition.normalizedURL),
            ("path", definition.normalizedPath),
            ("interval", definition.normalizedInterval > 0 ? String(definition.normalizedInterval) : nil)
        ]

        for (key, value) in values {
            let matchingIndex = (block.start + 1..<end).first {
                indentation(of: lines[$0]) == childIndent && mappingKey(in: lines[$0]) == key
            }
            if let matchingIndex {
                if let value {
                    lines[matchingIndex] = renderedScalarLine(replacing: lines[matchingIndex], value: value)
                } else if inlineComment(in: lines[matchingIndex]).isEmpty {
                    lines.remove(at: matchingIndex)
                    end -= 1
                } else {
                    lines[matchingIndex] = String(repeating: " ", count: childIndent) + inlineComment(in: lines[matchingIndex])
                }
            } else if let value {
                lines.insert(String(repeating: " ", count: childIndent) + "\(key): \(yamlScalar(value))", at: end)
                end += 1
            }
        }
    }

    private func append(_ provider: NodeProvider, to lines: inout [String], section: YAMLSection) {
        let blocks = providerBlocks(in: lines, section: section)
        let providerIndent = blocks.first?.indent ?? 2
        let childIndent = providerIndent + 2
        var entry = [String(repeating: " ", count: providerIndent) + "\(provider.name):"]
        let definition = provider.definition
        entry.append(String(repeating: " ", count: childIndent) + "type: \(yamlScalar(definition.normalizedType))")
        if definition.normalizedURL.isEmpty == false {
            entry.append(String(repeating: " ", count: childIndent) + "url: \(yamlScalar(definition.normalizedURL))")
        }
        entry.append(String(repeating: " ", count: childIndent) + "path: \(yamlScalar(definition.normalizedPath))")
        if definition.normalizedInterval > 0 {
            entry.append(String(repeating: " ", count: childIndent) + "interval: \(definition.normalizedInterval)")
        }
        lines.insert(contentsOf: entry, at: section.end)
    }

    private func topLevelKey(in line: String) -> String? {
        guard indentation(of: line) == 0 else { return nil }
        return mappingKey(in: line)
    }

    private func mappingKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false, trimmed.hasPrefix("#") == false, trimmed.hasPrefix("-") == false,
              let colon = trimmed.firstIndex(of: ":")
        else { return nil }
        let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
        guard key.isEmpty == false, key.contains(" ") == false else { return nil }
        return String(key)
    }

    private func scalarValue(in line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        let raw = String(line[line.index(after: colon)...])
        let withoutComment: String
        if let comment = raw.range(of: " #") {
            withoutComment = String(raw[..<comment.lowerBound])
        } else {
            withoutComment = raw
        }
        let trimmed = withoutComment.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2,
           ((trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private func renderedScalarLine(replacing line: String, value: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        let prefix = String(line[...colon])
        let comment = inlineComment(in: line)
        return "\(prefix) \(yamlScalar(value))\(comment)"
    }

    private func inlineComment(in line: String) -> String {
        guard let range = line.range(of: " #") else { return "" }
        let hash = line.index(after: range.lowerBound)
        var commentStart = hash
        while commentStart > line.startIndex {
            let previous = line.index(before: commentStart)
            guard line[previous] == " " || line[previous] == "\t" else { break }
            commentStart = previous
        }
        let comment = String(line[commentStart...])
        return comment.trimmingCharacters(in: .whitespaces).isEmpty ? "" : comment
    }

    private func yamlScalar(_ value: String) -> String {
        let needsQuotes = value.isEmpty || value.hasPrefix("-") || value.hasPrefix("?") || value.hasPrefix("!")
            || value.contains(" #") || value.contains(": ") || value.contains("\n")
        guard needsQuotes else { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func indentation(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    func syncError(_ message: String) -> NSError {
        NSError(domain: "Mihomo.NodeProviderProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

import Foundation

enum URLDisplayText {
    private static let fallback = "远程 URL（已隐藏参数）"

    static func redactingSensitiveComponents(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false
        else { return fallback }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.percentEncodedPath = redactedPath(components.percentEncodedPath)
        return components.string ?? fallback
    }

    private static func redactedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                let encoded = String(segment)
                let decoded = encoded.removingPercentEncoding ?? encoded
                return looksLikeSensitiveToken(decoded) ? "redacted" : encoded
            }
            .joined(separator: "/")
    }

    private static func looksLikeSensitiveToken(_ segment: String) -> Bool {
        let lowercased = segment.lowercased()
        let visibleFileExtensions = [".yaml", ".yml", ".json", ".txt", ".conf", ".list"]
        if visibleFileExtensions.contains(where: lowercased.hasSuffix) {
            return false
        }

        let scalars = segment.unicodeScalars
        let tokenCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard scalars.isEmpty == false,
              scalars.allSatisfy(tokenCharacters.contains)
        else { return false }

        let compact = segment.filter { $0.isLetter || $0.isNumber }
        let hasLetter = compact.contains(where: \.isLetter)
        let hasNumber = compact.contains(where: \.isNumber)
        let hasLowercase = compact.contains(where: \.isLowercase)
        let hasUppercase = compact.contains(where: \.isUppercase)

        if hasLetter == false {
            return compact.count >= 16
        }
        guard hasNumber else { return false }
        return compact.count >= 24
            || (compact.count >= 16 && hasLowercase && hasUppercase)
    }
}

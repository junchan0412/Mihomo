import Foundation

struct DiagnosticRedactor {
    private static let placeholder = "<redacted>"

    private let sensitiveValues: [String]

    init(settings: AppSettings) {
        sensitiveValues = [
            settings.controllerSecret,
            settings.backupWebDAVPassword,
            settings.gistToken
        ]
    }

    func redact(_ content: String) -> String {
        var result = content
        result = replace(
            #"(?im)^([ \t-]*(?:secret|password|passwd|token|authorization|proxy-authorization|controllerSecret|backupWebDAVPassword|gistToken)[ \t:=]+).*$"#,
            in: result,
            with: "$1\(Self.placeholder)"
        )
        result = replace(
            #"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+"#,
            in: result,
            with: "$1 \(Self.placeholder)"
        )
        result = replace(
            #"(?i)([?&](?:token|secret|password|passwd|key|auth|access_token)=)[^&\s]+"#,
            in: result,
            with: "$1\(Self.placeholder)"
        )
        result = replace(
            #"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#,
            in: result,
            with: "$1\(Self.placeholder)@"
        )

        for value in Set(sensitiveValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where value.count >= 4 {
            result = result.replacingOccurrences(of: value, with: Self.placeholder)
        }
        return result
    }

    var manifest: String {
        """
        Diagnostic Redaction
        Applied: controller secret values, Authorization/Bearer/Basic credentials, password/token/secret lines, URL user-info, and sensitive query parameters are replaced with \(Self.placeholder).
        """
    }

    private func replace(_ pattern: String, in content: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return content }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return expression.stringByReplacingMatches(in: content, range: range, withTemplate: template)
    }
}

import CryptoKit
import Foundation
import Security

final class CertificatePinningSession: NSObject, URLSessionDelegate {
    private let expectedFingerprint: String?
    private var pinningError: Error?
    private(set) var observedFingerprint: String?

    init(expectedFingerprint: String?) {
        let cleaned = CertificatePinningSession.normalize(expectedFingerprint ?? "")
        self.expectedFingerprint = cleaned.isEmpty ? nil : cleaned
    }

    func fetch(_ url: URL) async throws -> (Data, URLResponse, String?) {
        let session = URLSession(configuration: NetworkSessionFactory.configuration(for: .api), delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        if let pinningError {
            throw pinningError
        }
        return (data, response, observedFingerprint)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var trustError: CFError?
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        guard SecTrustEvaluateWithError(trust, &trustError),
              let certificate = chain?.first
        else {
            pinningError = trustError as Error?
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        observedFingerprint = digest

        if let expectedFingerprint, expectedFingerprint != digest {
            pinningError = NSError(domain: "CertificatePinning", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "证书指纹不匹配：期望 \(expectedFingerprint)，实际 \(digest)"
            ])
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

    static func normalize(_ value: String) -> String {
        value.lowercased()
            .filter { $0.isHexDigit }
            .map(String.init)
            .joined()
    }
}

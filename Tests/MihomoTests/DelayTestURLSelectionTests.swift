import XCTest
@testable import Mihomo

final class DelayTestURLSelectionTests: XCTestCase {
    func testProxyAndDirectTargetsUseIndependentConfiguredURLs() {
        var settings = AppSettings.default
        settings.delayTestURL = "https://proxy.example.com/generate_204"
        settings.directDelayTestURL = "https://direct.example.com/generate_204"

        let proxyURLs = DelayTestURLSelection.proxyURLs(settings: settings)
        let directURLs = DelayTestURLSelection.directURLs(settings: settings)

        XCTAssertEqual(proxyURLs.first, "https://proxy.example.com/generate_204")
        XCTAssertEqual(directURLs.first, "https://direct.example.com/generate_204")
        XCTAssertFalse(proxyURLs.contains("https://direct.example.com/generate_204"))
        XCTAssertFalse(directURLs.contains("https://proxy.example.com/generate_204"))
    }
}

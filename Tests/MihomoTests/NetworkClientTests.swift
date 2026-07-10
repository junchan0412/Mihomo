import XCTest
@testable import Mihomo

final class NetworkClientTests: XCTestCase {
    func testNetworkRequestKindTimeoutsAreBoundedByUseCase() {
        let api = NetworkSessionFactory.configuration(for: .api)
        XCTAssertEqual(api.timeoutIntervalForRequest, 20)
        XCTAssertEqual(api.timeoutIntervalForResource, 60)

        let download = NetworkSessionFactory.configuration(for: .download)
        XCTAssertEqual(download.timeoutIntervalForRequest, 30)
        XCTAssertEqual(download.timeoutIntervalForResource, 300)

        let controller = NetworkSessionFactory.configuration(for: .controller)
        XCTAssertEqual(controller.timeoutIntervalForRequest, 8)
        XCTAssertEqual(controller.timeoutIntervalForResource, 15)
    }

    func testNetworkSessionsDoNotWaitIndefinitelyForConnectivity() {
        for kind in [NetworkRequestKind.api, .download, .controller] {
            let configuration = NetworkSessionFactory.configuration(for: kind)
            XCTAssertFalse(configuration.waitsForConnectivity)
            XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        }
    }
}

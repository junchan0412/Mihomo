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

    func testControllerSessionUsesBoundedControllerTimeouts() {
        let configuration = NetworkSessionFactory.session(for: .controller).configuration

        XCTAssertEqual(configuration.timeoutIntervalForRequest, NetworkRequestKind.controller.requestTimeout)
        XCTAssertEqual(configuration.timeoutIntervalForResource, NetworkRequestKind.controller.resourceTimeout)
        XCTAssertFalse(configuration.waitsForConnectivity)
    }

    func testEventStreamSessionOutlivesTheControllerResourceBudget() {
        let configuration = NetworkSessionFactory.eventStreamSession.configuration

        // timeoutIntervalForResource caps a task's total lifetime, WebSocket tasks included.
        // Reusing the controller session tore every event stream down after 15 s.
        XCTAssertGreaterThan(
            configuration.timeoutIntervalForResource,
            NetworkRequestKind.controller.resourceTimeout
        )
        XCTAssertGreaterThan(configuration.timeoutIntervalForResource, 3600)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, NetworkRequestKind.controller.requestTimeout)
        XCTAssertFalse(configuration.waitsForConnectivity)
    }
}

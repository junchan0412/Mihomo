import XCTest
@testable import Mihomo

final class SoftwareUpdateProgressTests: XCTestCase {
    func testDownloadProgressHandlesKnownAndUnknownSizes() {
        let known = SoftwareUpdateDownloadProgress(
            bytesReceived: 512,
            totalBytes: 1024,
            bytesPerSecond: 256
        )
        XCTAssertEqual(known.fractionCompleted, 0.5)
        XCTAssertFalse(known.isIndeterminate)
        XCTAssertTrue(known.transferDescription.contains("/"))

        let unknown = SoftwareUpdateDownloadProgress(
            bytesReceived: 1536,
            totalBytes: nil,
            bytesPerSecond: 512
        )
        XCTAssertNil(unknown.fractionCompleted)
        XCTAssertTrue(unknown.isIndeterminate)
        XCTAssertFalse(unknown.transferDescription.contains("/"))
    }

    func testPhaseAllowsCancellationOnlyBeforeSystemChanges() {
        XCTAssertTrue(SoftwareUpdatePhase.checking.isCancellable)
        XCTAssertTrue(SoftwareUpdatePhase.downloading(.init(bytesReceived: 0, totalBytes: nil, bytesPerSecond: 0)).isCancellable)
        XCTAssertTrue(SoftwareUpdatePhase.verifying.isCancellable)
        XCTAssertFalse(SoftwareUpdatePhase.preparingNetwork.isCancellable)
        XCTAssertFalse(SoftwareUpdatePhase.preparingHelper.isCancellable)
        XCTAssertFalse(SoftwareUpdatePhase.installing.isCancellable)
        XCTAssertFalse(SoftwareUpdatePhase.readyToRestart.isInProgress)
    }

    func testPhaseProvidesActionSpecificCancellationTitles() {
        XCTAssertEqual(SoftwareUpdatePhase.checking.cancellationTitle, "取消检查")
        XCTAssertEqual(
            SoftwareUpdatePhase.downloading(.init(bytesReceived: 0, totalBytes: nil, bytesPerSecond: 0)).cancellationTitle,
            "取消下载"
        )
        XCTAssertEqual(SoftwareUpdatePhase.verifying.cancellationTitle, "取消验证")
        XCTAssertNil(SoftwareUpdatePhase.readyToRestart.cancellationTitle)
        XCTAssertNil(SoftwareUpdatePhase.failed.cancellationTitle)
    }
}

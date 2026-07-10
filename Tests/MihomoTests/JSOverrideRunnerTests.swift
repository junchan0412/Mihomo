import XCTest
@testable import Mihomo

final class JSOverrideRunnerTests: XCTestCase {
    func testWorkerAppliesTransform() throws {
        let runner = JSOverrideRunner(workerURL: workerURL)
        let fragment = javascriptFragment("function transform(config) { return config + '\\n# transformed'; }")

        XCTAssertEqual(try runner.apply(fragments: [fragment], to: "mixed-port: 7890"), "mixed-port: 7890\n# transformed")
    }

    func testInfiniteLoopTimesOutAndReturnsControl() {
        let runner = JSOverrideRunner(workerURL: workerURL)
        let fragment = javascriptFragment("function transform(config) { while (true) {} }")
        let startedAt = Date()

        XCTAssertThrowsError(try runner.apply(fragments: [fragment], to: "mixed-port: 7890")) { error in
            XCTAssertTrue(error.localizedDescription.contains("执行超时"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
    }

    func testOversizedFragmentIsRejectedBeforeWorkerLaunch() {
        let runner = JSOverrideRunner(workerURL: workerURL)
        let fragment = javascriptFragment(String(repeating: "x", count: JSOverrideRunner.maximumFragmentBytes + 1))

        XCTAssertThrowsError(try runner.apply(fragments: [fragment], to: "mixed-port: 7890")) { error in
            XCTAssertTrue(error.localizedDescription.contains("不能超过 64 KiB"))
        }
    }

    func testOversizedTransformOutputIsRejected() {
        let runner = JSOverrideRunner(workerURL: workerURL)
        let fragment = javascriptFragment("function transform(config) { return 'x'.repeat(2097153); }")

        XCTAssertThrowsError(try runner.apply(fragments: [fragment], to: "mixed-port: 7890")) { error in
            XCTAssertTrue(error.localizedDescription.contains("输出超过 2 MiB"))
        }
    }

    private var workerURL: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/MihomoJSWorker")
    }

    private func javascriptFragment(_ content: String) -> ConfigFragment {
        ConfigFragment(name: "Test", kind: .javascript, enabled: true, content: content)
    }
}

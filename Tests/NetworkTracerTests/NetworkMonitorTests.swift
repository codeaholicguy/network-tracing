import XCTest
@testable import NetworkTracerCore

@MainActor
final class NetworkMonitorTests: XCTestCase {

    func test_start_updatesStoreWithParsedConnections() async throws {
        let lsofLine = "curl 1 u 5u IPv4 0x0 0t0 TCP 10.0.0.1:9999->1.2.3.4:443 (ESTABLISHED)"
        let monitor = NetworkMonitor(pollInterval: 0.05, dataProvider: { lsofLine })
        let store = ConnectionStore()

        await monitor.start(store: store)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(store.connections.isEmpty)
        XCTAssertEqual(store.connections.first?.remoteAddress, "1.2.3.4:443")
        XCTAssertEqual(store.connections.first?.processName, "curl")
    }

    func test_start_withEmptyData_storeRemainsEmpty() async throws {
        let monitor = NetworkMonitor(pollInterval: 0.05, dataProvider: { "" })
        let store = ConnectionStore()

        await monitor.start(store: store)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(store.connections.isEmpty)
    }

    func test_start_withEmptyData_existingRecordsRetainedWithinStaleWindow() async throws {
        let store = ConnectionStore()
        store.update(with: [ParsedConnection(remoteAddress: "1.2.3.4:443", processName: "curl")])
        XCTAssertEqual(store.connections.count, 1)

        let monitor = NetworkMonitor(pollInterval: 0.05, dataProvider: { "" })
        await monitor.start(store: store)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.connections.count, 1, "Record within stale window should not be evicted")
    }

    func test_stop_preventsMonitorTaskFromRunning() async throws {
        let box = SendableBox(0)
        let monitor = NetworkMonitor(pollInterval: 0.02, dataProvider: {
            box.increment()
            return ""
        })
        let store = ConnectionStore()

        await monitor.start(store: store)
        try await Task.sleep(for: .milliseconds(60))
        await monitor.stop()

        let countAtStop = box.value
        XCTAssertGreaterThan(countAtStop, 0, "Should have polled at least once before stop")

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(box.value, countAtStop, "No further polls after stop")
    }

    func test_pollInterval_isCorrectForDefaultInit() async {
        let monitor = NetworkMonitor()
        let interval = await monitor.pollInterval
        XCTAssertEqual(interval, 5.0)
    }

    /// Integration test: exercises the real lsof subprocess path.
    /// Skip in CI with `SKIP_INTEGRATION_TESTS=1`.
    func test_integration_realLSOF_doesNotCrash() async throws {
        guard ProcessInfo.processInfo.environment["SKIP_INTEGRATION_TESTS"] == nil else {
            throw XCTSkip("Integration tests skipped")
        }
        let store = ConnectionStore()
        let monitor = NetworkMonitor()
        await monitor.start(store: store)
        try await Task.sleep(for: .seconds(6))
        await monitor.stop()
    }
}

/// Thread-safe integer box for test call-count tracking.
final class SendableBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int
    init(_ initial: Int) { _value = initial }
    func increment() { lock.withLock { _value += 1 } }
    var value: Int { lock.withLock { _value } }
}

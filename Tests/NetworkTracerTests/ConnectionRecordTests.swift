import XCTest
@testable import NetworkTracerCore

final class ConnectionRecordTests: XCTestCase {

    func test_displayName_withHostname_returnsHostnameAndPort() {
        let record = makeRecord(remote: "142.250.80.46:443", hostname: "api.example.com")
        XCTAssertEqual(record.displayName, "api.example.com:443")
    }

    func test_displayName_nilHostname_returnsRawAddress() {
        let record = makeRecord(remote: "142.250.80.46:443")
        XCTAssertEqual(record.displayName, "142.250.80.46:443")
    }

    func test_ipAddress_extractsIPv4() {
        XCTAssertEqual(makeRecord(remote: "192.168.1.1:80").ipAddress, "192.168.1.1")
    }

    func test_ipAddress_extractsIPv6() {
        XCTAssertEqual(makeRecord(remote: "[::1]:8080").ipAddress, "::1")
    }

    func test_displayName_withIPv6AndHostname() {
        let record = makeRecord(remote: "[::1]:8080", hostname: "localhost")
        XCTAssertEqual(record.displayName, "localhost:8080")
    }

    func test_hashable_deduplicatesInSet() {
        let a = makeRecord(remote: "1.2.3.4:443", process: "curl")
        let b = makeRecord(remote: "1.2.3.4:443", process: "curl")
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func test_differentProcesses_notDeduplicated() {
        let a = makeRecord(remote: "1.2.3.4:443", process: "curl")
        let b = makeRecord(remote: "1.2.3.4:443", process: "Safari")
        XCTAssertEqual(Set([a, b]).count, 2)
    }

    // MARK: - Helpers

    private func makeRecord(remote: String, process: String = "curl", hostname: String? = nil) -> ConnectionRecord {
        ConnectionRecord(
            id: "\(process)|\(remote)",
            remoteAddress: remote,
            processName: process,
            hostname: hostname,
            lastSeen: .now
        )
    }
}

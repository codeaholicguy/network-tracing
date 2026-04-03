import XCTest
@testable import NetworkTracerCore

@MainActor
final class ConnectionStoreTests: XCTestCase {
    var store: ConnectionStore!

    override func setUp() async throws {
        store = ConnectionStore()
    }

    // MARK: - Helpers

    private func conn(_ remote: String, process: String = "curl") -> ParsedConnection {
        ParsedConnection(remoteAddress: remote, processName: process)
    }

    private func id(_ remote: String, process: String = "curl") -> String {
        "\(process)|\(remote)"
    }

    // MARK: - Tests

    func test_update_newAddress_createsRecord() {
        store.update(with: [conn("142.250.80.46:443")])
        XCTAssertEqual(store.connections.count, 1)
        XCTAssertEqual(store.connections.first?.id, id("142.250.80.46:443"))
        XCTAssertEqual(store.connections.first?.processName, "curl")
        XCTAssertTrue(store.connections.first!.lastSeen.timeIntervalSinceNow > -1)
    }

    func test_update_existingAddress_updatesLastSeen() {
        store.update(with: [conn("142.250.80.46:443")])
        let past = Date(timeIntervalSinceNow: -5)
        store.connections[0] = makeRecord("142.250.80.46:443", lastSeen: past)

        store.update(with: [conn("142.250.80.46:443")])
        XCTAssertEqual(store.connections.count, 1)
        XCTAssertGreaterThan(store.connections[0].lastSeen, past)
    }

    func test_update_staleAddress_removed() {
        store.update(with: [conn("142.250.80.46:443")])
        store.connections[0] = makeRecord("142.250.80.46:443", lastSeen: Date(timeIntervalSinceNow: -20))

        store.update(with: [conn("17.57.144.20:443")])
        XCTAssertFalse(store.connections.contains { $0.id == id("142.250.80.46:443") })
        XCTAssertTrue(store.connections.contains { $0.id == id("17.57.144.20:443") })
    }

    func test_update_sortedNewestFirst() {
        store.connections = [
            makeRecord("a.com:80",  lastSeen: Date(timeIntervalSinceNow: -5)),
            makeRecord("b.com:443", lastSeen: Date(timeIntervalSinceNow: -1)),
        ]
        store.update(with: [conn("a.com:80")])
        XCTAssertEqual(store.connections.first?.id, id("a.com:80"))
        XCTAssertEqual(store.connections.last?.id,  id("b.com:443"))
    }

    func test_update_emptyAddresses_keepsWithinStaleWindow() {
        store.update(with: [conn("142.250.80.46:443")])
        store.update(with: [])
        XCTAssertEqual(store.connections.count, 1)
    }

    func test_update_differentProcessSameRemote_twoRows() {
        store.update(with: [
            conn("1.2.3.4:443", process: "curl"),
            conn("1.2.3.4:443", process: "Safari"),
        ])
        XCTAssertEqual(store.connections.count, 2)
    }

    func test_update_exceedsMaxConnections_dropsOldest() {
        let now = Date()
        store.connections = (0..<501).map { i in
            makeRecord("10.0.\(i/256).\(i%256):1000", lastSeen: now.addingTimeInterval(TimeInterval(i)))
        }
        store.update(with: [conn(store.connections[0].remoteAddress)])
        XCTAssertLessThanOrEqual(store.connections.count, 500)
    }

    func test_applyHostname_updatesExistingRecord() {
        store.update(with: [conn("1.2.3.4:443")])
        store.applyHostname("example.com", forID: id("1.2.3.4:443"))
        XCTAssertEqual(store.connections.first?.hostname, "example.com")
        XCTAssertEqual(store.connections.first?.displayName, "example.com:443")
    }

    func test_applyHostname_unknownID_noOp() {
        store.update(with: [conn("1.2.3.4:443")])
        store.applyHostname("ghost.com", forID: "unknown|9.9.9.9:80")
        XCTAssertNil(store.connections.first?.hostname)
    }

    func test_applyOrg_updatesExistingRecord() {
        store.update(with: [conn("1.2.3.4:443")])
        store.applyOrg("Google LLC", forID: id("1.2.3.4:443"))
        XCTAssertEqual(store.connections.first?.org, "Google LLC")
    }

    func test_applyOrg_unknownID_noOp() {
        store.update(with: [conn("1.2.3.4:443")])
        store.applyOrg("Ghost Inc", forID: "unknown|9.9.9.9:80")
        XCTAssertNil(store.connections.first?.org)
    }

    func test_update_hostnameAndOrgPreservedOnRefresh() {
        store.update(with: [conn("142.250.80.46:443")])
        store.connections[0] = makeRecord("142.250.80.46:443", hostname: "api.example.com", org: "Example Inc")
        store.update(with: [conn("142.250.80.46:443")])
        XCTAssertEqual(store.connections.first?.hostname, "api.example.com")
        XCTAssertEqual(store.connections.first?.org, "Example Inc")
    }

    // MARK: - Factory

    private func makeRecord(_ remote: String, process: String = "curl", hostname: String? = nil, org: String? = nil, lastSeen: Date = .now) -> ConnectionRecord {
        ConnectionRecord(id: "\(process)|\(remote)", remoteAddress: remote, processName: process, hostname: hostname, org: org, lastSeen: lastSeen)
    }
}

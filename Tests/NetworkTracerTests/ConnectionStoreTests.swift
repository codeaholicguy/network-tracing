import XCTest
@testable import NetworkTracerCore

@MainActor
final class ConnectionStoreTests: XCTestCase {
    var store: ConnectionStore!
    var tempDirectory: URL!
    var acceptedPatternStore: AcceptedPatternStore!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnectionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        acceptedPatternStore = try AcceptedPatternStore(fileURL: tempDirectory.appendingPathComponent("accepted-patterns.json"))
        store = ConnectionStore(acceptedPatternStore: acceptedPatternStore)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
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

    func test_update_marksNewRowsNeedsAttentionWhenNoAcceptedPatternExists() {
        store.update(with: [conn("1.2.3.4:443")])

        XCTAssertEqual(store.connections.first?.attention.state, .needsAttention)
        XCTAssertEqual(store.connections.first?.attention.message, "Not accepted yet")
        XCTAssertEqual(store.attentionCount, 1)
    }

    func test_init_loadsAcceptedPatternsAndUpdateMarksMatchingRowsAccepted() throws {
        let pattern = AcceptedHighlightPattern(processName: "curl", value: "1.2.3.4:443")
        try acceptedPatternStore.save([patternID(for: pattern): pattern])
        store = ConnectionStore(acceptedPatternStore: acceptedPatternStore)

        store.update(with: [conn("1.2.3.4:443")])

        XCTAssertEqual(store.acceptedPatterns[patternID(for: pattern)], pattern)
        XCTAssertEqual(store.connections.first?.attention.state, .accepted)
        XCTAssertEqual(store.attentionCount, 0)
    }

    func test_applyHostnameReevaluatesAttentionAgainstAcceptedHostnameValue() throws {
        let pattern = AcceptedHighlightPattern(processName: "curl", value: "example.com:443")
        try acceptedPatternStore.save([patternID(for: pattern): pattern])
        store = ConnectionStore(acceptedPatternStore: acceptedPatternStore)
        store.update(with: [conn("1.2.3.4:443")])

        XCTAssertEqual(store.connections.first?.attention.state, .needsAttention)

        store.applyHostname("example.com", forID: id("1.2.3.4:443"))

        XCTAssertEqual(store.connections.first?.attention.state, .accepted)
    }

    func test_applyOrgDoesNotChangeAttentionState() {
        store.update(with: [conn("1.2.3.4:443")])

        store.applyOrg("Example Org", forID: id("1.2.3.4:443"))

        XCTAssertEqual(store.connections.first?.org, "Example Org")
        XCTAssertEqual(store.connections.first?.attention.state, .needsAttention)
    }

    func test_acceptEndpointPersistsPatternAndReevaluatesVisibleRows() throws {
        store.update(with: [conn("1.2.3.4:443")])
        store.applyOrg("Example Org", forID: id("1.2.3.4:443"))

        try store.acceptEndpoint(forID: id("1.2.3.4:443"))

        let expected = AcceptedHighlightPattern(processName: "curl", value: "1.2.3.4:443", org: "Example Org")
        XCTAssertEqual(store.acceptedPatterns[patternID(for: expected)], expected)
        XCTAssertEqual(store.connections.first?.attention.state, .accepted)
        XCTAssertEqual(try acceptedPatternStore.load()[patternID(for: expected)], expected)
    }

    func test_acceptEndpointSaveFailureDoesNotMutateAcceptedPatterns() throws {
        let fileURL = tempDirectory.appendingPathComponent("directory-instead-of-file", isDirectory: true)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let patternStore = try AcceptedPatternStore(fileURL: fileURL)
        store = ConnectionStore(acceptedPatternStore: patternStore)
        store.update(with: [conn("1.2.3.4:443")])

        XCTAssertThrowsError(try store.acceptEndpoint(forID: id("1.2.3.4:443")))
        XCTAssertTrue(store.acceptedPatterns.isEmpty)
        XCTAssertEqual(store.connections.first?.attention.state, .needsAttention)
    }

    func test_acceptEndpointUsesHostnameValueWhenAvailable() throws {
        store.update(with: [conn("1.2.3.4:443")])
        store.applyHostname("example.com", forID: id("1.2.3.4:443"))

        try store.acceptEndpoint(forID: id("1.2.3.4:443"))

        let expected = AcceptedHighlightPattern(processName: "curl", value: "example.com:443")
        XCTAssertEqual(store.acceptedPatterns[patternID(for: expected)], expected)
    }

    func test_acceptAllNeedingAttentionPersistsPatternsAndReevaluatesRows() throws {
        store.update(with: [
            conn("1.2.3.4:443", process: "curl"),
            conn("5.6.7.8:443", process: "Safari")
        ])
        store.applyHostname("example.com", forID: id("1.2.3.4:443", process: "curl"))
        store.applyOrg("Example Org", forID: id("1.2.3.4:443", process: "curl"))

        let acceptedCount = try store.acceptAllNeedingAttention()

        let curlPattern = AcceptedHighlightPattern(processName: "curl", value: "example.com:443", org: "Example Org")
        let safariPattern = AcceptedHighlightPattern(processName: "Safari", value: "5.6.7.8:443")
        XCTAssertEqual(acceptedCount, 2)
        XCTAssertEqual(store.attentionCount, 0)
        XCTAssertEqual(store.acceptedPatterns[patternID(for: curlPattern)], curlPattern)
        XCTAssertEqual(store.acceptedPatterns[patternID(for: safariPattern)], safariPattern)
        XCTAssertEqual(try acceptedPatternStore.load()[patternID(for: curlPattern)], curlPattern)
        XCTAssertEqual(try acceptedPatternStore.load()[patternID(for: safariPattern)], safariPattern)
    }

    func test_acceptAllNeedingAttentionSaveFailureDoesNotMutateAcceptedPatterns() throws {
        let fileURL = tempDirectory.appendingPathComponent("directory-instead-of-file", isDirectory: true)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let patternStore = try AcceptedPatternStore(fileURL: fileURL)
        store = ConnectionStore(acceptedPatternStore: patternStore)
        store.update(with: [
            conn("1.2.3.4:443", process: "curl"),
            conn("5.6.7.8:443", process: "Safari")
        ])

        XCTAssertThrowsError(try store.acceptAllNeedingAttention())
        XCTAssertTrue(store.acceptedPatterns.isEmpty)
        XCTAssertEqual(store.attentionCount, 2)
    }

    func test_removeAcceptedPatternMakesMatchingRowsNeedAttentionAgain() throws {
        store.update(with: [conn("1.2.3.4:443")])
        try store.acceptEndpoint(forID: id("1.2.3.4:443"))
        let acceptedID = store.connections.first!.attention.acceptedPatternID

        try store.removeAcceptedPattern(id: acceptedID)

        XCTAssertNil(store.acceptedPatterns[acceptedID])
        XCTAssertEqual(store.connections.first?.attention.state, .needsAttention)
    }

    func test_importAcceptedPatternsReevaluatesExistingRows() throws {
        store.update(with: [conn("1.2.3.4:443")])
        let importURL = tempDirectory.appendingPathComponent("import.json")
        try """
        {
          "curl--1-2-3-4-443": {
            "processName": "curl",
            "value": "1.2.3.4:443"
          }
        }
        """.data(using: .utf8)!.write(to: importURL)

        let summary = try store.importAcceptedPatterns(from: importURL)

        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(store.connections.first?.attention.state, .accepted)
    }

    func test_needsAttentionOnlyFiltersAcceptedRows() throws {
        store.update(with: [
            conn("1.2.3.4:443", process: "curl"),
            conn("5.6.7.8:443", process: "Safari")
        ])
        try store.acceptEndpoint(forID: id("1.2.3.4:443", process: "curl"))

        store.needsAttentionOnly = true

        XCTAssertEqual(store.visibleConnections.map(\.processName), ["Safari"])
        XCTAssertEqual(store.attentionCount, 1)
    }

    // MARK: - Factory

    private func makeRecord(_ remote: String, process: String = "curl", hostname: String? = nil, org: String? = nil, lastSeen: Date = .now) -> ConnectionRecord {
        ConnectionRecord(id: "\(process)|\(remote)", remoteAddress: remote, processName: process, hostname: hostname, org: org, lastSeen: lastSeen)
    }

    private func patternID(for pattern: AcceptedHighlightPattern) -> String {
        AcceptedPatternID.make(processName: pattern.processName, value: pattern.value)
    }
}

import XCTest
@testable import NetworkTracerCore

final class AcceptedPatternStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkTracerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func test_load_missingFile_returnsEmptyDictionary() throws {
        let store = try makeStore()

        XCTAssertEqual(try store.load(), [:])
    }

    func test_saveAndLoad_roundTripsObjectKeyedByID() throws {
        let store = try makeStore()
        let patterns = acceptedPatterns([
            .init(processName: "Safari", value: "example.com:443", org: "Cloudflare, Inc.")
        ])

        try store.save(patterns)

        XCTAssertEqual(try store.load(), patterns)
    }

    func test_save_createsNetworkTracerDirectory() throws {
        let url = tempDirectory
            .appendingPathComponent("Nested", isDirectory: true)
            .appendingPathComponent("accepted-patterns.json")
        let store = try AcceptedPatternStore(fileURL: url)

        try store.save(acceptedPatterns([.init(processName: "curl", value: "192.168.1.1:80")]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_defaultFileURL_usesNetworkTracerAcceptedPatternsPath() throws {
        let url = try AcceptedPatternStore.defaultFileURL()

        XCTAssertEqual(url.lastPathComponent, "accepted-patterns.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "NetworkTracer")
    }

    func test_export_writesOnlyAcceptedPatternJSON() throws {
        let store = try makeStore()
        let exportURL = tempDirectory.appendingPathComponent("export.json")
        let patterns = acceptedPatterns([
            .init(processName: "node", value: "example.com:3000")
        ])

        try store.export(patterns, to: exportURL)
        let exported = try String(contentsOf: exportURL)

        XCTAssertTrue(exported.contains("\"processName\""))
        XCTAssertTrue(exported.contains("\"value\""))
        XCTAssertFalse(exported.contains("lastSeen"))
        XCTAssertFalse(exported.contains("remoteAddress"))
        XCTAssertFalse(exported.contains("hostname"))
    }

    func test_import_validJSON_addsPatternAndSaves() throws {
        let store = try makeStore()
        var patterns: [String: AcceptedHighlightPattern] = [:]
        let importURL = try writeImportJSON("""
        {
          "safari--example-com-443": {
            "processName": "Safari",
            "value": "example.com:443",
            "org": "Cloudflare, Inc."
          }
        }
        """)

        let summary = try store.importPatterns(from: importURL, into: &patterns)

        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(patterns["safari--example-com-443"]?.org, "Cloudflare, Inc.")
        XCTAssertEqual(try store.load(), patterns)
    }

    func test_import_malformedJSON_throwsWithoutMutating() throws {
        let store = try makeStore()
        var patterns = acceptedPatterns([
            .init(processName: "curl", value: "192.168.1.1:80")
        ])
        let original = patterns
        let importURL = try writeImportJSON("{")

        XCTAssertThrowsError(try store.importPatterns(from: importURL, into: &patterns)) { error in
            XCTAssertEqual(error as? AcceptedPatternStoreError, .invalidJSON)
        }
        XCTAssertEqual(patterns, original)
    }

    func test_import_topLevelArray_throwsWithoutMutating() throws {
        let store = try makeStore()
        var patterns = acceptedPatterns([
            .init(processName: "curl", value: "192.168.1.1:80")
        ])
        let original = patterns
        let importURL = try writeImportJSON("[]")

        XCTAssertThrowsError(try store.importPatterns(from: importURL, into: &patterns)) { error in
            XCTAssertEqual(error as? AcceptedPatternStoreError, .topLevelObjectRequired)
        }
        XCTAssertEqual(patterns, original)
    }

    func test_import_saveFailure_throwsWithoutMutating() throws {
        let fileURL = tempDirectory.appendingPathComponent("directory-instead-of-file", isDirectory: true)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let store = try AcceptedPatternStore(fileURL: fileURL)
        var patterns = acceptedPatterns([
            .init(processName: "curl", value: "192.168.1.1:80")
        ])
        let original = patterns
        let importURL = try writeImportJSON("""
        {
          "safari--example-com-443": {
            "processName": "Safari",
            "value": "example.com:443"
          }
        }
        """)

        XCTAssertThrowsError(try store.importPatterns(from: importURL, into: &patterns))
        XCTAssertEqual(patterns, original)
    }

    func test_saveFailure_doesNotReplaceExistingPath() throws {
        let fileURL = tempDirectory.appendingPathComponent("directory-instead-of-file", isDirectory: true)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let store = try AcceptedPatternStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.save(acceptedPatterns([
            .init(processName: "Safari", value: "example.com:443")
        ])))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func test_import_rejectsInvalidRecordsAndAddsValidRecords() throws {
        let store = try makeStore()
        var patterns: [String: AcceptedHighlightPattern] = [:]
        let importURL = try writeImportJSON("""
        {
          "": {
            "processName": "Safari",
            "value": "example.com:443"
          },
          "bad--missing-value": {
            "processName": "Safari"
          },
          "bad--org": {
            "processName": "Safari",
            "value": "example.com:8443",
            "org": 123
          },
          "node--example-com-3000": {
            "processName": "node",
            "value": "example.com:3000"
          }
        }
        """)

        let summary = try store.importPatterns(from: importURL, into: &patterns)

        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.rejected, 3)
        XCTAssertNotNil(patterns["node--example-com-3000"])
    }

    func test_import_sameIDDifferentRecord_rejectsConflict() throws {
        let store = try makeStore()
        var patterns = [
            "curl--example-com-443": AcceptedHighlightPattern(processName: "curl", value: "example.com:443")
        ]
        let importURL = try writeImportJSON("""
        {
          "curl--example-com-443": {
            "processName": "Safari",
            "value": "example.com:443"
          }
        }
        """)

        let summary = try store.importPatterns(from: importURL, into: &patterns)

        XCTAssertEqual(summary.rejected, 1)
        XCTAssertEqual(patterns["curl--example-com-443"]?.processName, "curl")
    }

    func test_import_nonCanonicalID_rejectsRecord() throws {
        let store = try makeStore()
        var patterns: [String: AcceptedHighlightPattern] = [:]
        let importURL = try writeImportJSON("""
        {
          "legacy--key": {
            "processName": "curl",
            "value": "example.com:443"
          }
        }
        """)

        let summary = try store.importPatterns(from: importURL, into: &patterns)

        XCTAssertEqual(summary.rejected, 1)
        XCTAssertNil(patterns["legacy--key"])
    }

    func test_import_duplicateIDCanFillMissingOrgButNotOverwriteExistingOrg() throws {
        let store = try makeStore()
        var patterns = [
            "curl--example-com-443": AcceptedHighlightPattern(processName: "curl", value: "example.com:443"),
            "safari--example-com-443": AcceptedHighlightPattern(processName: "Safari", value: "example.com:443", org: "Existing Org")
        ]
        let importURL = try writeImportJSON("""
        {
          "curl--example-com-443": {
            "processName": "curl",
            "value": "example.com:443",
            "org": "Filled Org"
          },
          "safari--example-com-443": {
            "processName": "Safari",
            "value": "example.com:443",
            "org": "Imported Org"
          }
        }
        """)

        let summary = try store.importPatterns(from: importURL, into: &patterns)

        XCTAssertEqual(summary.duplicates, 2)
        XCTAssertEqual(summary.filledMissingOrg, 1)
        XCTAssertEqual(patterns["curl--example-com-443"]?.org, "Filled Org")
        XCTAssertEqual(patterns["safari--example-com-443"]?.org, "Existing Org")
    }

    private func makeStore(fileName: String = "accepted-patterns.json") throws -> AcceptedPatternStore {
        try AcceptedPatternStore(fileURL: tempDirectory.appendingPathComponent(fileName))
    }

    private func writeImportJSON(_ json: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent("import-\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: url)
        return url
    }

    private func acceptedPatterns(_ patterns: [AcceptedHighlightPattern]) -> [String: AcceptedHighlightPattern] {
        Dictionary(uniqueKeysWithValues: patterns.map { pattern in
            (patternID(for: pattern), pattern)
        })
    }

    private func patternID(for pattern: AcceptedHighlightPattern) -> String {
        AcceptedPatternID.make(processName: pattern.processName, value: pattern.value)
    }
}

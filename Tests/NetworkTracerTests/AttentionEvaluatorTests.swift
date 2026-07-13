import XCTest
@testable import NetworkTracerCore

final class AttentionEvaluatorTests: XCTestCase {
    func test_idGeneration_usesProcessAndValueSlugs() {
        XCTAssertEqual(
            AcceptedPatternID.make(processName: "Safari", value: "example.com"),
            "safari--example-com"
        )
        XCTAssertEqual(
            AcceptedPatternID.make(processName: "node", value: "example.com:3000"),
            "node--example-com-3000"
        )
        XCTAssertEqual(
            AcceptedPatternID.make(processName: "curl", value: "192.168.1.1"),
            "curl--192-168-1-1"
        )
    }

    func test_idGeneration_ignoresOrg() {
        let withoutOrg = AcceptedHighlightPattern(processName: "Safari", value: "example.com")
        let withOrg = AcceptedHighlightPattern(processName: "Safari", value: "example.com", org: "Cloudflare, Inc.")

        XCTAssertEqual(patternID(for: withoutOrg), patternID(for: withOrg))
    }

    func test_slug_trimsLowercasesAndCollapsesSeparators() {
        XCTAssertEqual(AcceptedPatternID.slug("  Google Chrome  "), "google-chrome")
        XCTAssertEqual(AcceptedPatternID.slug("example.com:443"), "example-com-443")
        XCTAssertEqual(AcceptedPatternID.slug("[2606:4700:4700::1111]:443"), "2606-4700-4700-1111-443")
    }

    func test_evaluate_acceptsHostnameAndPort() {
        let record = makeRecord(remote: "93.184.216.34:443", process: "Safari", hostname: "example.com")
        let patterns = acceptedPatterns([
            .init(processName: "Safari", value: "example.com:443")
        ])

        let result = AttentionEvaluator().evaluate(record: record, acceptedPatterns: patterns)

        XCTAssertEqual(result.state, .accepted)
        XCTAssertEqual(result.acceptedPatternID, "safari--example-com-443")
    }

    func test_evaluate_acceptsIPAndPort() {
        let record = makeRecord(remote: "192.168.1.1:80", process: "curl")
        let patterns = acceptedPatterns([
            .init(processName: "curl", value: "192.168.1.1:80")
        ])

        let result = AttentionEvaluator().evaluate(record: record, acceptedPatterns: patterns)

        XCTAssertEqual(result.state, .accepted)
    }

    func test_evaluate_needsAttentionWhenNoAcceptedPatternMatches() {
        let record = makeRecord(remote: "192.168.1.1:80", process: "curl")

        let result = AttentionEvaluator().evaluate(record: record, acceptedPatterns: [:])

        XCTAssertEqual(result.state, .needsAttention)
        XCTAssertEqual(result.message, "Not accepted yet")
        XCTAssertEqual(result.acceptedPatternID, "curl--192-168-1-1-80")
    }

    func test_evaluate_prefersHostnameCandidateWhenAvailable() {
        let record = makeRecord(remote: "93.184.216.34:443", process: "Safari", hostname: "example.com")

        let result = AttentionEvaluator().evaluate(record: record, acceptedPatterns: [:])

        XCTAssertEqual(result.acceptedPatternID, "safari--example-com-443")
    }

    func test_evaluate_canAcceptIPAfterHostnameEnrichment() {
        let record = makeRecord(remote: "93.184.216.34:443", process: "Safari", hostname: "example.com")
        let patterns = acceptedPatterns([
            .init(processName: "Safari", value: "93.184.216.34:443")
        ])

        let result = AttentionEvaluator().evaluate(record: record, acceptedPatterns: patterns)

        XCTAssertEqual(result.state, .accepted)
        XCTAssertEqual(result.acceptedPatternID, "safari--93-184-216-34-443")
    }

    func test_evaluate_doesNotAcceptDifferentPort() {
        let record = makeRecord(remote: "93.184.216.34:8443", process: "Safari", hostname: "example.com")
        let patterns = acceptedPatterns([
            .init(processName: "Safari", value: "example.com:443")
        ])

        let result = AttentionEvaluator().evaluate(record: record, acceptedPatterns: patterns)

        XCTAssertEqual(result.state, .needsAttention)
    }

    func test_evaluate_doesNotRequireOrg() {
        let record = makeRecord(remote: "93.184.216.34:443", process: "Safari", hostname: "example.com")
        let patterns = acceptedPatterns([
            .init(processName: "Safari", value: "example.com:443", org: nil)
        ])

        let result = AttentionEvaluator().evaluate(record: record, acceptedPatterns: patterns)

        XCTAssertEqual(result.state, .accepted)
    }

    func test_evaluate_requiresCanonicalPatternID() {
        let record = makeRecord(remote: "93.184.216.34:443", process: "Safari", hostname: "example.com")
        let patterns = [
            "legacy-key": AcceptedHighlightPattern(processName: "Safari", value: "example.com:443")
        ]

        let result = AttentionEvaluator().evaluate(record: record, acceptedPatterns: patterns)

        XCTAssertEqual(result.state, .needsAttention)
        XCTAssertEqual(result.acceptedPatternID, "safari--example-com-443")
    }

    private func makeRecord(remote: String, process: String, hostname: String? = nil) -> ConnectionRecord {
        ConnectionRecord(
            id: "\(process)|\(remote)",
            remoteAddress: remote,
            processName: process,
            hostname: hostname,
            lastSeen: .now
        )
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

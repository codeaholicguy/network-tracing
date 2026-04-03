import XCTest
@testable import NetworkTracerCore

final class DNSResolverTests: XCTestCase {

    // MARK: - Reverse DNS (hostname)

    /// Loopback always has a PTR record — no external network needed.
    func test_resolveHostname_loopback_returnsLocalhost() async {
        let resolver = DNSResolver()
        let result = await resolver.resolveHostname(ip: "127.0.0.1")
        XCTAssertEqual(result, "localhost")
    }

    func test_resolveHostname_ipv6Loopback_returnsLocalhost() async {
        let resolver = DNSResolver()
        let result = await resolver.resolveHostname(ip: "::1")
        XCTAssertEqual(result, "localhost")
    }

    func test_resolveHostname_cachesResult() async {
        let resolver = DNSResolver()
        let first  = await resolver.resolveHostname(ip: "127.0.0.1")
        let second = await resolver.resolveHostname(ip: "127.0.0.1")
        XCTAssertNotNil(second)
        XCTAssertEqual(first, second)
    }

    // MARK: - Reverse DNS unit helper

    func test_reverseResolve_invalidIP_returnsNil() {
        XCTAssertNil(DNSResolver.reverseResolve(ip: "not-an-ip"))
    }

    func test_reverseResolve_loopback_returnsLocalhost() {
        XCTAssertEqual(DNSResolver.reverseResolve(ip: "127.0.0.1"), "localhost")
    }

    // MARK: - Org lookup (integration — requires network)

    func test_resolveOrg_knownIP_returnsOrgName() async throws {
        guard ProcessInfo.processInfo.environment["SKIP_INTEGRATION_TESTS"] == nil else {
            throw XCTSkip("Integration tests skipped")
        }
        let resolver = DNSResolver()
        // 8.8.8.8 is Google's DNS — ipinfo.io returns "Google LLC"
        let result = await resolver.resolveOrg(ip: "8.8.8.8")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isEmpty)
    }

    func test_resolveOrg_cachesResult() async throws {
        guard ProcessInfo.processInfo.environment["SKIP_INTEGRATION_TESTS"] == nil else {
            throw XCTSkip("Integration tests skipped")
        }
        let resolver = DNSResolver()
        let first  = await resolver.resolveOrg(ip: "8.8.8.8")
        let second = await resolver.resolveOrg(ip: "8.8.8.8")
        XCTAssertEqual(first, second)
    }
}

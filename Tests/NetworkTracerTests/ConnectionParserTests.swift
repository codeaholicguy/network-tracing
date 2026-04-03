import XCTest
@testable import NetworkTracerCore

final class ConnectionParserTests: XCTestCase {

    func test_emptyString_returnsEmpty() {
        XCTAssertEqual(ConnectionParser.parse(""), [])
    }

    func test_noArrowLines_returnsEmpty() {
        let input = """
        COMMAND PID USER FD TYPE DEVICE SIZE NODE NAME
        daemon  123 user 3u IPv4 0x0    0t0  UDP  *:5353
        """
        XCTAssertEqual(ConnectionParser.parse(input), [])
    }

    func test_singleEstablishedLine_returnsRemoteAndProcess() {
        let input = "curl 1234 user 5u IPv4 0x0 0t0 TCP 192.168.1.5:54321->142.250.80.46:443 (ESTABLISHED)"
        let result = ConnectionParser.parse(input)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.remoteAddress, "142.250.80.46:443")
        XCTAssertEqual(result.first?.processName, "curl")
    }

    func test_deduplicatesSameProcessAndRemote() {
        let input = """
        curl 1234 user 5u IPv4 0x0 0t0 TCP 192.168.1.5:54321->142.250.80.46:443 (ESTABLISHED)
        curl 1234 user 6u IPv4 0x0 0t0 TCP 192.168.1.5:54322->142.250.80.46:443 (ESTABLISHED)
        """
        let result = ConnectionParser.parse(input)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.remoteAddress, "142.250.80.46:443")
        XCTAssertEqual(result.first?.processName, "curl")
    }

    func test_differentProcessesSameRemote_returnsTwoRows() {
        let input = """
        curl   1234 user 5u IPv4 0x0 0t0 TCP 192.168.1.5:1->142.250.80.46:443 (ESTABLISHED)
        Safari 5678 user 6u IPv4 0x0 0t0 TCP 192.168.1.5:2->142.250.80.46:443 (ESTABLISHED)
        """
        let result = ConnectionParser.parse(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(ParsedConnection(remoteAddress: "142.250.80.46:443", processName: "curl")))
        XCTAssertTrue(result.contains(ParsedConnection(remoteAddress: "142.250.80.46:443", processName: "Safari")))
    }

    func test_ignoresStarStarRemotes() {
        let input = "daemon 99 user 3u IPv4 0x0 0t0 UDP *:*"
        XCTAssertEqual(ConnectionParser.parse(input), [])
    }

    func test_ignoresListeningWildcardRemotes() {
        let input = "node 555 user 20u IPv6 0x0 0t0 TCP *:3000 (LISTEN)"
        XCTAssertEqual(ConnectionParser.parse(input), [])
    }

    func test_multipleLines_returnsAllUnique() {
        let input = """
        curl   1234 user  5u IPv4 0x0 0t0 TCP 192.168.1.5:54321->142.250.80.46:443 (ESTABLISHED)
        Safari 5678 user 12u IPv4 0x0 0t0 TCP 192.168.1.5:60001->17.57.144.20:443 (ESTABLISHED)
        """
        let result = ConnectionParser.parse(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.remoteAddress == "142.250.80.46:443" && $0.processName == "curl" })
        XCTAssertTrue(result.contains { $0.remoteAddress == "17.57.144.20:443" && $0.processName == "Safari" })
    }

    // MARK: - cleanProcessName

    func test_cleanProcessName_plainName_unchanged() {
        XCTAssertEqual(ConnectionParser.cleanProcessName("Safari"), "Safari")
        XCTAssertEqual(ConnectionParser.cleanProcessName("curl"), "curl")
    }

    func test_cleanProcessName_stripsParentheticalSuffix() {
        XCTAssertEqual(ConnectionParser.cleanProcessName("Google Chrome Helper (Renderer)"), "Google Chrome Helper")
        XCTAssertEqual(ConnectionParser.cleanProcessName("Google Chrome Helper (GPU)"), "Google Chrome Helper")
    }

    func test_cleanProcessName_reverseDomain_takesLastComponent() {
        XCTAssertEqual(ConnectionParser.cleanProcessName("com.apple.WebKit.Networking"), "Networking")
        XCTAssertEqual(ConnectionParser.cleanProcessName("com.apple.Safari"), "Safari")
        XCTAssertEqual(ConnectionParser.cleanProcessName("org.mozilla.firefox"), "firefox")
    }

    func test_cleanProcessName_withVersionSuffix_unchanged() {
        XCTAssertEqual(ConnectionParser.cleanProcessName("python3.11"), "python3.11")
        XCTAssertEqual(ConnectionParser.cleanProcessName("node"), "node")
    }

    func test_handlesIPv6Address() {
        let input = "ssh 999 user 3u IPv6 0x0 0t0 TCP [::1]:52789->[::1]:8080 (ESTABLISHED)"
        let result = ConnectionParser.parse(input)
        XCTAssertEqual(result.first?.remoteAddress, "[::1]:8080")
        XCTAssertEqual(result.first?.processName, "ssh")
    }

    // MARK: - unescapeLSOF

    func test_unescapeLSOF_noEscapes_unchanged() {
        XCTAssertEqual(ConnectionParser.unescapeLSOF("curl"), "curl")
        XCTAssertEqual(ConnectionParser.unescapeLSOF("Safari"), "Safari")
        XCTAssertEqual(ConnectionParser.unescapeLSOF(""), "")
    }

    func test_unescapeLSOF_spaceEscape() {
        XCTAssertEqual(ConnectionParser.unescapeLSOF("Google\\x20Chrome"), "Google Chrome")
    }

    func test_unescapeLSOF_openParenEscape() {
        XCTAssertEqual(ConnectionParser.unescapeLSOF("App\\x28Helper\\x29"), "App(Helper)")
    }

    func test_unescapeLSOF_multipleEscapes() {
        XCTAssertEqual(ConnectionParser.unescapeLSOF("A\\x20B\\x20C"), "A B C")
    }

    func test_unescapeLSOF_bareBackslash_passedThrough() {
        // Lone backslash not followed by 'x' — pass through literally
        XCTAssertEqual(ConnectionParser.unescapeLSOF("a\\b"), "a\\b")
    }

    func test_unescapeLSOF_backslashX_noDigits_passedThrough() {
        // "\x" with no hex digits after it — pass through literally
        XCTAssertEqual(ConnectionParser.unescapeLSOF("\\x"), "\\x")
    }

    func test_cleanProcessName_unescapesHexBeforeStripping() {
        // lsof may emit: "Google\x20Chrome\x20Helper\x20(Renderer)"
        XCTAssertEqual(
            ConnectionParser.cleanProcessName("Google\\x20Chrome\\x20Helper\\x20(Renderer)"),
            "Google Chrome Helper"
        )
    }

    func test_parse_hexEscapedProcessName_unescaped() {
        let input = "Google\\x20Chrome 1234 user 5u IPv4 0x0 0t0 TCP 10.0.0.1:50001->142.250.80.46:443 (ESTABLISHED)"
        let result = ConnectionParser.parse(input)
        XCTAssertEqual(result.first?.processName, "Google Chrome")
    }
}

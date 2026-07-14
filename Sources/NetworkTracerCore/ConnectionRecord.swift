import Foundation

public struct ConnectionRecord: Identifiable, Hashable, Sendable {
    /// Stable dedup key — "processName|ip:port" (unique per app + remote endpoint)
    public let id: String
    public var remoteAddress: String
    public var processName: String      // COMMAND field from lsof (e.g. "curl", "Safari")
    public var hostname: String?        // PTR record hostname (e.g. "dns.google")
    public var org: String?             // owning organisation from ipinfo.io (e.g. "Google LLC")
    public var lastSeen: Date
    public var attention: AttentionResult

    public init(id: String, remoteAddress: String, processName: String,
                hostname: String? = nil, org: String? = nil, lastSeen: Date,
                attention: AttentionResult? = nil) {
        self.id = id
        self.remoteAddress = remoteAddress
        self.processName = processName
        self.hostname = hostname
        self.org = org
        self.lastSeen = lastSeen
        self.attention = attention ?? .needsAttention(
            patternID: AcceptedPatternID.make(
                processName: processName,
                value: Self.endpointValue(remoteAddress: remoteAddress, hostname: hostname)
            )
        )
    }

    public static func == (lhs: ConnectionRecord, rhs: ConnectionRecord) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// "hostname:port" when resolved, otherwise raw "ip:port"
    public var displayName: String {
        guard let hostname else { return remoteAddress }
        let port = Self.extractPort(from: remoteAddress) ?? ""
        return port.isEmpty ? hostname : "\(hostname):\(port)"
    }

    /// Value copied from the popover host column.
    public var copyableHostPort: String { displayName }

    /// IP address without port, suitable for reverse DNS lookup
    public var ipAddress: String { Self.extractIP(from: remoteAddress) }

    public func endpointValues(preferHostname: Bool = true) -> [String] {
        let ipValue = remoteAddress
        guard let hostname else { return [ipValue] }

        let hostnameValue = Self.endpointValue(remoteAddress: remoteAddress, hostname: hostname)

        if hostnameValue == ipValue {
            return [ipValue]
        }
        return preferHostname ? [hostnameValue, ipValue] : [ipValue, hostnameValue]
    }

    /// Strips the port from an address string, returning the bare IP.
    /// Handles both IPv4 ("1.2.3.4:443" → "1.2.3.4") and IPv6 ("[::1]:8080" → "::1").
    public static func extractIP(from address: String) -> String {
        if address.hasPrefix("["),
           let start = address.firstIndex(of: "["),
           let end   = address.firstIndex(of: "]") {
            return String(address[address.index(after: start)..<end])
        }
        let parts = address.components(separatedBy: ":")
        guard parts.count >= 2 else { return address }
        return parts.dropLast().joined(separator: ":")
    }

    static func extractPort(from address: String) -> String? {
        if address.hasPrefix("[") {
            // IPv6 "[::1]:8080" → "8080"
            guard let bracket = address.lastIndex(of: "]") else { return nil }
            let afterBracket = address.index(after: bracket)
            guard afterBracket < address.endIndex, address[afterBracket] == ":" else { return nil }
            return String(address[address.index(after: afterBracket)...])
        }
        // IPv4 "192.168.1.1:443" → "443"
        return address.components(separatedBy: ":").last
    }

    static func endpointValue(remoteAddress: String, hostname: String?) -> String {
        guard let hostname else { return remoteAddress }
        let port = extractPort(from: remoteAddress) ?? ""
        return port.isEmpty ? hostname : "\(hostname):\(port)"
    }
}

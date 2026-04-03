import Foundation

/// A single parsed network connection from lsof output.
public struct ParsedConnection: Hashable, Sendable {
    public let remoteAddress: String   // "ip:port"
    public let processName: String     // COMMAND field (e.g. "curl", "Safari")
}

/// Parses raw `lsof -i` output into unique (processName, remoteAddress) pairs.
public enum ConnectionParser {

    /// Returns deduplicated connections from lsof output.
    /// Only lines containing "->" (connected sockets) are included;
    /// listening sockets (*:port) and wildcard remotes (*:*) are excluded.
    public static func parse(_ output: String) -> [ParsedConnection] {
        var seen = Set<ParsedConnection>()
        for line in output.components(separatedBy: "\n") {
            if let conn = extractConnection(from: line) {
                seen.insert(conn)
            }
        }
        return Array(seen)
    }

    /// Normalise a raw lsof COMMAND value into a short, readable app name.
    /// Rules applied in order:
    ///   1. Unescape lsof \xNN hex sequences (e.g. \x20 → space, \x28 → "(")
    ///   2. Strip parenthetical role suffixes e.g. " (Renderer)" → used by Chromium-family apps
    ///   3. Take the last dot-separated component for reverse-domain names
    ///      e.g. "com.apple.WebKit.Networking" → "Networking"
    ///   4. Trim whitespace
    static func cleanProcessName(_ raw: String) -> String {
        var name = unescapeLSOF(raw)
        // 2. Strip trailing " (…)" suffix
        if let paren = name.lastIndex(of: "("), name.hasSuffix(")") {
            let beforeParen = name[name.startIndex..<paren].trimmingCharacters(in: .whitespaces)
            if !beforeParen.isEmpty { name = beforeParen }
        }
        // 3. Reverse-domain style names — take last component
        let lower = name.lowercased()
        if name.contains(".") && (lower.hasPrefix("com.") || lower.hasPrefix("org.")) {
            name = name.components(separatedBy: ".").last ?? name
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Replace lsof \xNN hex escape sequences with the actual characters.
    /// lsof uses this encoding when a process name contains spaces or other
    /// special characters (e.g. "Google\x20Chrome" → "Google Chrome").
    static func unescapeLSOF(_ s: String) -> String {
        var result = ""
        var idx = s.startIndex
        while idx < s.endIndex {
            if s[idx] == "\\" {
                let next = s.index(after: idx)
                if next < s.endIndex, s[next] == "x" {
                    let hexStart = s.index(after: next)
                    let hexEnd   = s.index(hexStart, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                    if hexEnd <= s.endIndex,
                       let byte = UInt8(s[hexStart..<hexEnd], radix: 16) {
                        let scalar = Unicode.Scalar(byte)
                        result.append(Character(scalar))
                        idx = hexEnd
                        continue
                    }
                }
            }
            result.append(s[idx])
            idx = s.index(after: idx)
        }
        return result
    }

    // lsof NAME field format: "localAddr->remoteAddr (STATE)"
    // First field (COMMAND) is the process name.
    static func extractConnection(from line: String) -> ParsedConnection? {
        guard line.contains("->") else { return nil }

        // Extract remote address (right of "->")
        let parts = line.components(separatedBy: "->")
        guard parts.count >= 2 else { return nil }
        var remote = parts[parts.count - 1]

        // Strip trailing state annotation e.g. " (ESTABLISHED)"
        if let paren = remote.firstIndex(of: "(") {
            remote = String(remote[remote.startIndex..<paren])
        }
        remote = remote.trimmingCharacters(in: .whitespaces)

        // Exclude empty, wildcard-only, or listening-socket remotes
        guard !remote.isEmpty, remote != "*:*", !remote.hasPrefix("*") else { return nil }

        // Extract process name — first whitespace-separated token on the line
        let raw = line.split(separator: " ", omittingEmptySubsequences: true)
                      .first
                      .map(String.init) ?? "unknown"

        return ParsedConnection(remoteAddress: remote, processName: Self.cleanProcessName(raw))
    }
}

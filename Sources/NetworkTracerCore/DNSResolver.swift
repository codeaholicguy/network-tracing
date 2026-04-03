import Foundation

/// Resolves IP addresses to hostnames and org names independently.
///
/// - `resolveHostname(ip:)` — reverse DNS (PTR record), e.g. "dns.google"
/// - `resolveOrg(ip:)` — ipinfo.io org lookup, e.g. "Google LLC"
///
/// Both results are cached separately for the process lifetime.
/// Note: resolveOrg sends the IP to ipinfo.io (a third-party service).
public actor DNSResolver {
    public static let shared = DNSResolver()

    private var hostnameCache: [String: String] = [:]
    private var orgCache: [String: String] = [:]

    init() {}  // internal — allows fresh instances in tests; use .shared in production

    /// Reverse DNS lookup (PTR record). Returns nil if no PTR record exists.
    public func resolveHostname(ip: String) async -> String? {
        if let cached = hostnameCache[ip] { return cached }
        guard let hostname = await reverseDNS(ip: ip) else { return nil }
        hostnameCache[ip] = hostname
        return hostname
    }

    /// Org name from ipinfo.io (e.g. "Google LLC"). Returns nil on failure.
    public func resolveOrg(ip: String) async -> String? {
        if let cached = orgCache[ip] { return cached }
        guard let org = await fetchOrg(ip: ip) else { return nil }
        orgCache[ip] = org
        return org
    }

    // MARK: - Reverse DNS

    private func reverseDNS(ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                continuation.resume(returning: Self.reverseResolve(ip: ip))
            }
        }
    }

    // Blocking POSIX reverse-DNS lookup — runs on a background DispatchQueue thread,
    // not on Swift's cooperative thread pool, to avoid blocking other tasks.
    static func reverseResolve(ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST   // treat input as numeric IP, not hostname
        var res: UnsafeMutablePointer<addrinfo>?

        guard getaddrinfo(ip, nil, &hints, &res) == 0, let info = res else { return nil }
        defer { freeaddrinfo(res) }

        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let ret = getnameinfo(
            info.pointee.ai_addr, info.pointee.ai_addrlen,
            &hostBuf, socklen_t(hostBuf.count),
            nil, 0,
            NI_NAMEREQD   // return nil instead of falling back to raw IP
        )
        return ret == 0 ? String(cString: hostBuf) : nil
    }

    // MARK: - Org lookup (ipinfo.io)

    /// Fetches the owning organization for `ip` from ipinfo.io.
    /// Response format: "AS15169 Google LLC" — we strip the AS number prefix.
    /// Free tier: 50 000 requests/month (ample for a personal tool).
    private func fetchOrg(ip: String) async -> String? {
        guard let url = URL(string: "https://ipinfo.io/\(ip)/org") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let raw = String(data: data, encoding: .utf8)?
                          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Strip leading "AS##### " prefix if present
            if let spaceIdx = raw.firstIndex(of: " ") {
                let afterAS = String(raw[raw.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
                return afterAS.isEmpty ? nil : afterAS
            }
            return raw.isEmpty ? nil : raw
        } catch {
            return nil
        }
    }
}

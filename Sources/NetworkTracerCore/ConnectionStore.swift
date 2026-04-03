import Foundation

/// Observable state container for active network connections.
/// All mutations run on the MainActor to keep SwiftUI updates safe.
@MainActor
public final class ConnectionStore: ObservableObject {
    public static let shared = ConnectionStore()

    @Published public var connections: [ConnectionRecord] = []

    private let staleThreshold: TimeInterval = 15.0
    private let maxConnections = 500

    public init() {}

    /// Upsert `connections` into the connection list.
    /// - New (processName, remoteAddress) pairs get a fresh record and trigger async DNS resolution.
    /// - Existing pairs have their `lastSeen` updated.
    /// - Records not seen for longer than `staleThreshold` are removed.
    public func update(with incoming: [ParsedConnection]) {
        let now = Date()
        var map = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0) })

        for conn in incoming {
            let id = "\(conn.processName)|\(conn.remoteAddress)"
            if map[id] != nil {
                map[id]!.lastSeen = now
            } else {
                map[id] = ConnectionRecord(
                    id: id,
                    remoteAddress: conn.remoteAddress,
                    processName: conn.processName,
                    lastSeen: now
                )
                Task { await self.resolveAndApply(remoteAddress: conn.remoteAddress, id: id) }
            }
        }

        // Evict stale connections
        map = map.filter { now.timeIntervalSince($0.value.lastSeen) < staleThreshold }

        // Sort newest-first and cap size
        var sorted = map.values.sorted { $0.lastSeen > $1.lastSeen }
        if sorted.count > maxConnections {
            sorted = Array(sorted.prefix(maxConnections))
        }
        connections = sorted
    }

    /// Applies a resolved PTR hostname to an existing record.
    public func applyHostname(_ hostname: String, forID id: String) {
        guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].hostname = hostname
    }

    /// Applies a resolved org name to an existing record.
    public func applyOrg(_ org: String, forID id: String) {
        guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].org = org
    }

    private func resolveAndApply(remoteAddress: String, id: String) async {
        let ip = ConnectionRecord.extractIP(from: remoteAddress)
        if let hostname = await DNSResolver.shared.resolveHostname(ip: ip) {
            applyHostname(hostname, forID: id)
        }
        if let org = await DNSResolver.shared.resolveOrg(ip: ip) {
            applyOrg(org, forID: id)
        }
    }
}

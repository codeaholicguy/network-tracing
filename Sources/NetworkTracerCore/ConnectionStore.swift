import Foundation

public enum ConnectionStoreError: Error, Equatable {
    case acceptedPatternStoreUnavailable
    case connectionNotFound
}

/// Observable state container for active network connections.
/// All mutations run on the MainActor to keep SwiftUI updates safe.
@MainActor
public final class ConnectionStore: ObservableObject {
    public static let shared = ConnectionStore()

    @Published public var connections: [ConnectionRecord] = []
    @Published public var needsAttentionOnly = false

    @Published public private(set) var acceptedPatterns: [String: AcceptedHighlightPattern]

    private let staleThreshold: TimeInterval = 15.0
    private let maxConnections = 500
    private let acceptedPatternStore: AcceptedPatternStore?
    private let attentionEvaluator = AttentionEvaluator()

    public convenience init() {
        self.init(acceptedPatternStore: try? AcceptedPatternStore())
    }

    public init(acceptedPatternStore: AcceptedPatternStore?) {
        let loadedAcceptedPatterns = (try? acceptedPatternStore?.load()) ?? [:]
        self.acceptedPatternStore = acceptedPatternStore
        self.acceptedPatterns = loadedAcceptedPatterns
    }

    public var visibleConnections: [ConnectionRecord] {
        guard needsAttentionOnly else { return connections }
        return connections.filter { $0.attention.state == .needsAttention }
    }

    public var attentionCount: Int {
        connections.filter { $0.attention.state == .needsAttention }.count
    }

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
        connections = sorted.map(evaluateAttention)
    }

    /// Applies a resolved PTR hostname to an existing record.
    public func applyHostname(_ hostname: String, forID id: String) {
        guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].hostname = hostname
        connections[idx] = evaluateAttention(connections[idx])
    }

    /// Applies a resolved org name to an existing record.
    public func applyOrg(_ org: String, forID id: String) {
        guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].org = org
        connections[idx] = evaluateAttention(connections[idx])
    }

    public func acceptEndpoint(forID id: String) throws {
        guard let record = connections.first(where: { $0.id == id }) else {
            throw ConnectionStoreError.connectionNotFound
        }
        guard let store = acceptedPatternStore else {
            throw ConnectionStoreError.acceptedPatternStoreUnavailable
        }
        guard let value = record.endpointValues(preferHostname: true).first else {
            throw ConnectionStoreError.connectionNotFound
        }

        var updatedPatterns = acceptedPatterns
        let patternID = AcceptedPatternID.make(processName: record.processName, value: value)
        updatedPatterns[patternID] = acceptedPattern(for: record, value: value)
        try store.save(updatedPatterns)
        acceptedPatterns = updatedPatterns
        reevaluateAllConnections()
    }

    @discardableResult
    public func acceptAllNeedingAttention() throws -> Int {
        guard let store = acceptedPatternStore else {
            throw ConnectionStoreError.acceptedPatternStoreUnavailable
        }

        var updatedPatterns = acceptedPatterns
        var acceptedCount = 0
        for record in connections where record.attention.state == .needsAttention {
            guard let value = record.endpointValues(preferHostname: true).first else { continue }
            let patternID = AcceptedPatternID.make(processName: record.processName, value: value)
            updatedPatterns[patternID] = acceptedPattern(for: record, value: value)
            acceptedCount += 1
        }

        guard acceptedCount > 0 else { return 0 }
        try store.save(updatedPatterns)
        acceptedPatterns = updatedPatterns
        reevaluateAllConnections()
        return acceptedCount
    }

    public func removeAcceptedPattern(id: String) throws {
        guard let store = acceptedPatternStore else {
            throw ConnectionStoreError.acceptedPatternStoreUnavailable
        }
        var updatedPatterns = acceptedPatterns
        updatedPatterns.removeValue(forKey: id)
        try store.save(updatedPatterns)
        acceptedPatterns = updatedPatterns
        reevaluateAllConnections()
    }

    @discardableResult
    public func importAcceptedPatterns(from url: URL) throws -> ImportSummary {
        guard let store = acceptedPatternStore else {
            throw ConnectionStoreError.acceptedPatternStoreUnavailable
        }
        let summary = try store.importPatterns(from: url, into: &acceptedPatterns)
        reevaluateAllConnections()
        return summary
    }

    public func exportAcceptedPatterns(to url: URL) throws {
        guard let store = acceptedPatternStore else {
            throw ConnectionStoreError.acceptedPatternStoreUnavailable
        }
        try store.export(acceptedPatterns, to: url)
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

    private func evaluateAttention(_ record: ConnectionRecord) -> ConnectionRecord {
        var evaluated = record
        evaluated.attention = attentionEvaluator.evaluate(record: evaluated, acceptedPatterns: acceptedPatterns)
        return evaluated
    }

    private func acceptedPattern(for record: ConnectionRecord, value: String) -> AcceptedHighlightPattern {
        AcceptedHighlightPattern(
            processName: record.processName,
            value: value,
            org: record.org
        )
    }

    private func reevaluateAllConnections() {
        connections = connections.map(evaluateAttention)
    }
}

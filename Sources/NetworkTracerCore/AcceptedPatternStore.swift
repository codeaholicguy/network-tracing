import Foundation

public struct ImportSummary: Sendable, Hashable {
    public let added: Int
    public let duplicates: Int
    public let rejected: Int
    public let filledMissingOrg: Int

    public init(added: Int = 0, duplicates: Int = 0, rejected: Int = 0, filledMissingOrg: Int = 0) {
        self.added = added
        self.duplicates = duplicates
        self.rejected = rejected
        self.filledMissingOrg = filledMissingOrg
    }
}

public enum AcceptedPatternStoreError: Error, Equatable {
    case applicationSupportDirectoryUnavailable
    case invalidJSON
    case topLevelObjectRequired
}

public final class AcceptedPatternStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = try Self.defaultFileURL(fileManager: fileManager)
        }
    }

    public static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AcceptedPatternStoreError.applicationSupportDirectoryUnavailable
        }
        return appSupport
            .appendingPathComponent("NetworkTracer", isDirectory: true)
            .appendingPathComponent("accepted-patterns.json")
    }

    public func load() throws -> [String: AcceptedHighlightPattern] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: AcceptedHighlightPattern].self, from: data)
    }

    public func save(_ patterns: [String: AcceptedHighlightPattern]) throws {
        try write(patterns, to: fileURL)
    }

    public func export(_ patterns: [String: AcceptedHighlightPattern], to url: URL) throws {
        try write(patterns, to: url)
    }

    @discardableResult
    public func importPatterns(from url: URL, into patterns: inout [String: AcceptedHighlightPattern]) throws -> ImportSummary {
        let rawPatterns = try readImportObject(from: url)
        let result = Self.merge(rawPatterns, into: patterns)

        try save(result.patterns)
        patterns = result.patterns
        return result.summary
    }

    private func write(_ patterns: [String: AcceptedHighlightPattern], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(patterns)
        try data.write(to: url, options: .atomic)
    }

    private func readImportObject(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AcceptedPatternStoreError.invalidJSON
        }

        guard let rawPatterns = object as? [String: Any] else {
            throw AcceptedPatternStoreError.topLevelObjectRequired
        }
        return rawPatterns
    }

    private static func merge(
        _ rawPatterns: [String: Any],
        into existingPatterns: [String: AcceptedHighlightPattern]
    ) -> (patterns: [String: AcceptedHighlightPattern], summary: ImportSummary) {
        var patterns = existingPatterns
        var summary = ImportSummaryBuilder()

        for (id, rawValue) in rawPatterns {
            guard isValidID(id),
                  let imported = parsePattern(rawValue),
                  id == AcceptedPatternID.make(processName: imported.processName, value: imported.value) else {
                summary.rejected += 1
                continue
            }

            merge(id: id, imported: imported, into: &patterns, summary: &summary)
        }

        return (patterns, summary.makeSummary())
    }

    private static func merge(
        id: String,
        imported: AcceptedHighlightPattern,
        into patterns: inout [String: AcceptedHighlightPattern],
        summary: inout ImportSummaryBuilder
    ) {
        guard let existing = patterns[id] else {
            patterns[id] = imported
            summary.added += 1
            return
        }

        guard existing.matches(processName: imported.processName, value: imported.value) else {
            summary.rejected += 1
            return
        }

        summary.duplicates += 1
        if existing.org == nil, imported.org != nil {
            patterns[id] = imported
            summary.filledMissingOrg += 1
        }
    }

    private static func isValidID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == id && !id.isEmpty && id.contains("--")
    }

    private static func parsePattern(_ rawValue: Any) -> AcceptedHighlightPattern? {
        guard let object = rawValue as? [String: Any],
              let processName = object["processName"] as? String,
              let value = object["value"] as? String,
              !processName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let orgValue = object["org"], !(orgValue is String) {
            return nil
        }

        return AcceptedHighlightPattern(
            processName: processName,
            value: value,
            org: object["org"] as? String
        )
    }
}

private struct ImportSummaryBuilder {
    var added = 0
    var duplicates = 0
    var rejected = 0
    var filledMissingOrg = 0

    func makeSummary() -> ImportSummary {
        ImportSummary(
            added: added,
            duplicates: duplicates,
            rejected: rejected,
            filledMissingOrg: filledMissingOrg
        )
    }
}

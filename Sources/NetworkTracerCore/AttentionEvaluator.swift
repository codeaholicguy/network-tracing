import Foundation

public enum AttentionState: String, Sendable, Hashable {
    case accepted
    case needsAttention
}

public struct AttentionResult: Sendable, Hashable {
    public let state: AttentionState
    public let message: String
    public let acceptedPatternID: String

    public init(state: AttentionState, message: String, acceptedPatternID: String) {
        self.state = state
        self.message = message
        self.acceptedPatternID = acceptedPatternID
    }

    public static func accepted(patternID: String) -> AttentionResult {
        AttentionResult(state: .accepted, message: "Accepted", acceptedPatternID: patternID)
    }

    public static func needsAttention(patternID: String) -> AttentionResult {
        AttentionResult(state: .needsAttention, message: "Not accepted yet", acceptedPatternID: patternID)
    }
}

public struct AcceptedHighlightPattern: Codable, Sendable, Hashable {
    public let processName: String
    public let value: String
    public let org: String?

    public init(processName: String, value: String, org: String? = nil) {
        self.processName = processName
        self.value = value
        self.org = org
    }
}

public enum AcceptedPatternID {
    public static func make(processName: String, value: String) -> String {
        "\(slug(processName))--\(slug(value))"
    }

    public static func slug(_ value: String) -> String {
        var result = ""
        var previousWasSeparator = false

        for scalar in value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension AcceptedHighlightPattern {
    func matches(processName: String, value: String) -> Bool {
        self.processName == processName && self.value == value
    }
}

public struct AttentionEvaluator: Sendable {
    public init() {}

    public func evaluate(
        record: ConnectionRecord,
        acceptedPatterns: [String: AcceptedHighlightPattern]
    ) -> AttentionResult {
        let candidates = record.endpointValues(preferHostname: true)

        for value in candidates {
            let patternID = AcceptedPatternID.make(processName: record.processName, value: value)
            if acceptedPatterns[patternID]?.matches(processName: record.processName, value: value) == true {
                return .accepted(patternID: patternID)
            }
        }

        let firstValue = candidates.first ?? record.remoteAddress
        return .needsAttention(patternID: AcceptedPatternID.make(processName: record.processName, value: firstValue))
    }
}

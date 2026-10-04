import Foundation

/// Remembers what each setting was before Switchboard first changed it, so
/// "Restore Original Settings" can put everything back. A setting drops out once it's
/// back at its original value.
public struct OriginalSettings: Codable, Equatable, Sendable {
    public private(set) var values: [String: Bool] = [:]

    public init() {}

    public var isEmpty: Bool { values.isEmpty }

    public mutating func willChange(_ id: String, from current: Bool) {
        if values[id] == nil { values[id] = current }
    }

    public mutating func didChange(_ id: String, to new: Bool) {
        if values[id] == new { values[id] = nil }
    }

    public mutating func forget(_ id: String) {
        values[id] = nil
    }
}

public enum PreferenceValue {
    /// Reads a stored preference as a Bool. People often write these with
    /// `defaults write … -string YES`, so strings count too.
    public static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "1", "yes", "true": return true
            case "0", "no", "false": return false
            default: return nil
            }
        default:
            return nil
        }
    }
}

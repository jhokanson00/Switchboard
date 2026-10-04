import Foundation

/// A global keyboard shortcut, such as ⌃⌥⌘D.
public struct HotKey: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// The Mac symbols in the order Apple uses in menus: ⌃ ⌥ ⇧ ⌘.
        public var symbols: String {
            [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { contains($0.0) }
                .map(\.1)
                .joined()
        }
    }

    /// The key's virtual key code.
    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// The key's name as printed on it, e.g. "D", "F5", "Space".
    public var keyName: String

    public init(keyCode: UInt16, modifiers: Modifiers, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    /// What the shortcut field shows, e.g. "⌃⌥⌘D".
    public var label: String { modifiers.symbols + keyName }

    /// A global shortcut must not swallow ordinary typing, so it needs ⌘, ⌃ or ⌥ —
    /// unless it's a function key, which never types.
    public var isUsable: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || KeyNames.isFunctionKey(keyCode)
    }
}

/// Readable names for keys, by virtual key code.
public enum KeyNames {
    static let special: [UInt16: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    public static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeys[keyCode] != nil
    }

    /// The key's name: a symbol for special keys, otherwise the character it types with
    /// no modifiers in the current layout, capitalized as printed on the key.
    public static func name(keyCode: UInt16, characters: String?) -> String {
        if let name = functionKeys[keyCode] ?? special[keyCode] { return name }
        if let characters, characters.count == 1, let scalar = characters.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return characters.uppercased()
        }
        return "Key \(keyCode)"
    }
}

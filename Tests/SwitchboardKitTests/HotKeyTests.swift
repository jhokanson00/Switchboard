import Foundation
import Testing
@testable import SwitchboardKit

@Test func labelsUseMenuOrder() {
    let key = HotKey(keyCode: 2, modifiers: [.command, .shift, .control, .option], keyName: "D")
    #expect(key.label == "⌃⌥⇧⌘D")
}

@Test func plainOrShiftedTypingIsNotUsable() {
    #expect(!HotKey(keyCode: 2, modifiers: [], keyName: "D").isUsable)
    #expect(!HotKey(keyCode: 2, modifiers: [.shift], keyName: "D").isUsable)
    #expect(HotKey(keyCode: 2, modifiers: [.option], keyName: "D").isUsable)
    #expect(HotKey(keyCode: 2, modifiers: [.control, .shift], keyName: "D").isUsable)
}

@Test func functionKeysWorkAlone() {
    #expect(HotKey(keyCode: 96, modifiers: [], keyName: "F5").isUsable)
}

@Test func keyNamesPreferLayoutCharacters() {
    #expect(KeyNames.name(keyCode: 96, characters: nil) == "F5")
    #expect(KeyNames.name(keyCode: 49, characters: " ") == "Space")
    #expect(KeyNames.name(keyCode: 2, characters: "d") == "D")
    #expect(KeyNames.name(keyCode: 41, characters: "ö") == "Ö")
    #expect(KeyNames.name(keyCode: 2, characters: "\u{4}") == "Key 2")
}

@Test func hotKeysRoundTripThroughJSON() throws {
    let keys = ["darkMode": HotKey(keyCode: 2, modifiers: [.control, .option, .command], keyName: "D")]
    let data = try JSONEncoder().encode(keys)
    #expect(try JSONDecoder().decode([String: HotKey].self, from: data) == keys)
}

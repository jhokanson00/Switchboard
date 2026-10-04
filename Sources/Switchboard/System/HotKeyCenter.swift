import AppKit
import Carbon.HIToolbox
import SwitchboardKit

/// Global keyboard shortcuts as system hot keys: they work in any app, need no
/// permission, and cost nothing until pressed.
@MainActor
final class HotKeyCenter {
    /// Called with the id of the row or action whose shortcut was pressed.
    var onPress: ((String) -> Void)?
    /// Ids whose shortcut macOS refused, usually because another app already uses it.
    private(set) var refused: Set<String> = []

    private var registered: [UInt32: (id: String, ref: EventHotKeyRef)] = [:]
    private var handler: EventHandlerRef?
    private var nextNumber: UInt32 = 1
    private static let signature = OSType(0x5357_4244)  // "SWBD"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Replaces every registered shortcut.
    func register(_ keys: [String: HotKey]) {
        unregisterAll()
        refused = []
        for (id, key) in keys {
            var ref: EventHotKeyRef?
            let number = nextNumber
            nextNumber += 1
            let status = RegisterEventHotKey(
                UInt32(key.keyCode), Self.carbonModifiers(key.modifiers),
                EventHotKeyID(signature: Self.signature, id: number),
                GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[number] = (id, ref)
            } else {
                refused.insert(id)
            }
        }
    }

    func unregisterAll() {
        for (_, entry) in registered { UnregisterEventHotKey(entry.ref) }
        registered = [:]
    }

    fileprivate func pressed(number: UInt32) {
        guard let id = registered[number]?.id else { return }
        onPress?(id)
    }

    private static func carbonModifiers(_ modifiers: HotKey.Modifiers) -> UInt32 {
        var carbon = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        return UInt32(carbon)
    }
}

/// Runs on the main thread, where Carbon delivers application events.
private func hotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { center.pressed(number: hotKeyID.id) }
    return noErr
}

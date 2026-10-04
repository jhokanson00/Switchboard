import CoreAudio
import Foundation

/// Mutes the current output device (sound) or input device (microphone) through
/// CoreAudio, and follows it when the default device changes. Some devices (many USB
/// audio interfaces) have no mute control at all; the row says so instead of pretending.
@MainActor
final class AudioMute: SystemSetting {
    enum Direction {
        case output, input
    }

    let id: String
    let title: String
    let symbol: String
    let restorable = false

    private let direction: Direction
    private let scope: AudioObjectPropertyScope
    private let defaultDeviceAddress: AudioObjectPropertyAddress

    init(_ direction: Direction) {
        self.direction = direction
        switch direction {
        case .output:
            (id, title, symbol) = ("mute", "Mute", "speaker.slash")
            scope = kAudioDevicePropertyScopeOutput
        case .input:
            (id, title, symbol) = ("muteMicrophone", "Mute Microphone", "mic.slash")
            scope = kAudioDevicePropertyScopeInput
        }
        defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: direction == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var changed: (@MainActor () -> Void)?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?
    /// Elements the mute listener is attached to on `device`.
    private var listenedElements: [AudioObjectPropertyElement] = []

    private static let candidateElements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    func read() -> Reading {
        guard device != kAudioObjectUnknown else {
            return Reading(state: .unavailable(direction == .output ? "No sound output" : "No microphone"))
        }
        let name = deviceName() ?? (direction == .output ? "This output" : "This microphone")
        let elements = muteElements()
        guard let first = elements.first else {
            return Reading(state: .unavailable("\(name) has no mute control"))
        }
        var address = muteAddress(first)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return Reading(state: .unknown, detail: name)
        }
        return Reading(state: value != 0 ? .on : .off, detail: name)
    }

    func write(_ on: Bool) async throws {
        let elements = muteElements()
        guard !elements.isEmpty else { throw SwitchboardError.failed("This device has no mute control.") }
        var value: UInt32 = on ? 1 : 0
        for element in elements {
            var address = muteAddress(element)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            if status != noErr { throw SwitchboardError.failed("The output didn't accept the change (\(status)).") }
        }
    }

    func startObserving(_ changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        muteListener = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.changed?() }
        }
        let deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.followDefaultDevice()
                self?.changed?()
            }
        }
        self.deviceListener = deviceListener
        var address = defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(system, &address, .main, deviceListener)
        followDefaultDevice()
    }

    // MARK: Device

    private func followDefaultDevice() {
        if let muteListener {
            for element in listenedElements {
                var address = muteAddress(element)
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, muteListener)
            }
        }
        listenedElements = []

        var address = defaultDeviceAddress
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id)
        device = id

        guard let muteListener, device != kAudioObjectUnknown else { return }
        for element in Self.candidateElements {
            var address = muteAddress(element)
            if AudioObjectHasProperty(device, &address),
               AudioObjectAddPropertyListenerBlock(device, &address, .main, muteListener) == noErr {
                listenedElements.append(element)
            }
        }
    }

    /// The main mute control if there is one, else per-channel ones (left and right).
    private func muteElements() -> [AudioObjectPropertyElement] {
        let settable = Self.candidateElements.filter { element in
            var address = muteAddress(element)
            var isSettable: DarwinBoolean = false
            return AudioObjectHasProperty(device, &address)
                && AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr
                && isSettable.boolValue
        }
        return settable.contains(kAudioObjectPropertyElementMain) ? [kAudioObjectPropertyElementMain] : settable
    }

    private func muteAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: element)
    }

    private func deviceName() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

}

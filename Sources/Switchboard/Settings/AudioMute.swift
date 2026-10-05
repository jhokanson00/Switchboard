import CoreAudio
import Foundation
import Observation

/// Mutes the current output device (sound) or input device (microphone) through
/// CoreAudio, and follows it when the default device changes. Some devices (many USB
/// audio interfaces) have no mute control at all; the row says so instead of pretending.
/// The row's menu also switches the Mac to another output or microphone, like the Sound
/// menu in Control Center.
@MainActor
@Observable
final class AudioMute: SystemSetting {
    struct Device: Identifiable, Equatable {
        let id: AudioObjectID
        let name: String
    }

    enum Direction {
        case output, input
    }

    let id: String
    let title: String
    let symbol: String
    let restorable = false

    let direction: Direction
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
    /// The device the Mac is using now.
    private(set) var device = AudioObjectID(kAudioObjectUnknown)
    /// The devices it could switch to, by name.
    private(set) var devices: [Device] = []
    @ObservationIgnored private var changed: (@MainActor () -> Void)?
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var deviceListListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var muteListener: AudioObjectPropertyListenerBlock?
    /// Elements the mute listener is attached to on `device`.
    @ObservationIgnored private var listenedElements: [AudioObjectPropertyElement] = []

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

        // Devices plugged in or removed.
        let deviceListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.loadDevices() }
        }
        self.deviceListListener = deviceListListener
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(system, &devicesAddress, .main, deviceListListener)
        loadDevices()
    }

    /// Makes `id` the Mac's output or microphone. The row follows once CoreAudio reports it.
    func select(_ id: AudioObjectID) {
        guard id != device else { return }
        var address = defaultDeviceAddress
        var id = id
        AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
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

    /// Every device with sound going this way that macOS offers as a choice: not hidden,
    /// and allowed to be the default (as in Control Center's Sound menu).
    private func loadDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return }

        let found = ids.filter { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return false }
            return !flag(kAudioDevicePropertyIsHidden, of: id, scope: kAudioObjectPropertyScopeGlobal, default: false)
                && flag(kAudioDevicePropertyDeviceCanBeDefaultDevice, of: id, scope: scope, default: true)
        }
        .map { Device(id: $0, name: name(of: $0) ?? "Unnamed device") }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if found != devices { devices = found }
    }

    private func flag(_ selector: AudioObjectPropertySelector, of id: AudioObjectID, scope: AudioObjectPropertyScope, default fallback: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(id, &address),
              AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr
        else { return fallback }
        return value != 0
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
        name(of: device)
    }

    private func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

}

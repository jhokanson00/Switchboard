import AppKit
import CoreBluetooth
import IOBluetooth

/// Reads Bluetooth's power state through public CoreBluetooth, which also announces
/// changes. Switching it uses IOBluetoothPreferenceSetControllerPowerState, a private
/// function in the public IOBluetooth framework (what `blueutil` uses). It's looked up
/// at run time, so if it disappears the row says so instead of crashing.
@MainActor
final class Bluetooth: NSObject, SystemSetting, CBCentralManagerDelegate {
    let id = "bluetooth"
    let title = "Bluetooth"
    let symbol = "antenna.radiowaves.left.and.right"

    private typealias SetPowerFn = @convention(c) (Int32) -> Void
    private static let setPower: SetPowerFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
              let symbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { return nil }
        return unsafeBitCast(symbol, to: SetPowerFn.self)
    }()

    private var manager: CBCentralManager?
    private var changed: (@MainActor () -> Void)?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func read() -> Reading {
        switch CBManager.authorization {
        case .denied, .restricted:
            return Reading(state: .unavailable("Allow Bluetooth for Switchboard in Privacy & Security"))
        default:
            break
        }
        switch manager?.state {
        case .poweredOn: return Reading(state: Self.setPower == nil ? .unavailable("Can't be switched on this macOS") : .on)
        case .poweredOff: return Reading(state: Self.setPower == nil ? .unavailable("Can't be switched on this macOS") : .off)
        case .unsupported: return Reading(state: .unavailable("This Mac has no Bluetooth"))
        case .unauthorized: return Reading(state: .unavailable("Allow Bluetooth for Switchboard in Privacy & Security"))
        default: return Reading(state: .unknown)
        }
    }

    func write(_ on: Bool) async throws {
        guard let setPower = Self.setPower else { throw SwitchboardError.failed("Bluetooth can't be switched on this macOS.") }
        guard CBManager.authorization == .allowedAlways else { throw SwitchboardError.bluetoothDenied }
        setPower(on ? 1 : 0)
        // Return once CoreBluetooth reports the new state, so the row doesn't flick back.
        if manager?.state != (on ? .poweredOn : .poweredOff) {
            await waitForStateChange(timeout: .seconds(5))
        }
    }

    /// Turning Bluetooth off with a Bluetooth keyboard, mouse or trackpad connected can
    /// leave you unable to turn it back on, so ask first.
    func confirmChange(to on: Bool) async -> Bool {
        guard !on else { return true }
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let inputs = paired
            .filter { $0.isConnected() && $0.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral) }
            .map { $0.name ?? "A Bluetooth device" }
        guard !inputs.isEmpty else { return true }
        return Alerts.confirm(
            title: "Turn off Bluetooth?",
            message: "\(ListFormatter.localizedString(byJoining: inputs)) will disconnect. If that's your only keyboard or mouse, you'll need another one to turn Bluetooth back on.",
            confirm: "Turn Off")
    }

    func startObserving(_ changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        manager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            resumeWaiters()
            changed?()
        }
    }

    private func waitForStateChange(timeout: Duration) async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resumeWaiters()
            }
        }
    }

    private func resumeWaiters() {
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume() }
    }
}

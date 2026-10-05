import Foundation
import Observation

enum ControlState: Equatable {
    case on, off
    /// Can't be used right now; the reason is shown under the title.
    case unavailable(String)
    case unknown

    var isOn: Bool? {
        switch self {
        case .on: true
        case .off: false
        default: nil
        }
    }
}

struct Reading: Equatable {
    var state: ControlState
    /// Extra line under the title, e.g. "Until 3:00 PM".
    var detail: String? = nil
}

/// One system setting. Reading must be cheap (it runs every time the panel opens);
/// writing may be slow and runs as an async task.
@MainActor
protocol SystemSetting: AnyObject {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    /// Included in "Restore Original Settings". Off for momentary things like Mute.
    var restorable: Bool { get }
    /// macOS closes the menu bar panel when this changes; Switchboard opens it again.
    var closesPanel: Bool { get }

    func read() -> Reading
    func write(_ on: Bool) async throws
    /// A last chance to back out, e.g. before turning off Bluetooth with a Bluetooth
    /// keyboard connected.
    func confirmChange(to on: Bool) async -> Bool
    /// Settings that macOS announces changes for call `changed` when they do. The
    /// rest are read again when the panel opens.
    func startObserving(_ changed: @escaping @MainActor () -> Void)
    /// For a setting that needs a permission macOS hasn't asked about yet: asks. Nil
    /// otherwise. The row offers it while the setting reads as unavailable.
    var askForPermission: (() -> Void)? { get }
}

extension SystemSetting {
    var restorable: Bool { true }
    var closesPanel: Bool { false }
    func confirmChange(to on: Bool) async -> Bool { true }
    func startObserving(_ changed: @escaping @MainActor () -> Void) {}
    var askForPermission: (() -> Void)? { nil }
}

@MainActor
@Observable
final class Control: Identifiable {
    let setting: any SystemSetting
    private(set) var reading = Reading(state: .unknown)
    var isBusy = false
    var problem: SwitchboardError?

    nonisolated let id: String

    init(_ setting: any SystemSetting) {
        self.setting = setting
        self.id = setting.id
        setting.startObserving { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        let new = setting.read()
        if new != reading { reading = new }
    }
}

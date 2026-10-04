import Foundation
import ObjectiveC

/// Night Shift has no public API. This uses CoreBrightness's private CBBlueLightClient,
/// the class Control Center uses. Everything private is in this file; if the class or
/// its methods disappear in a future macOS, the row says so instead of crashing.
///
/// Turning it on is the same as "Turn On Until Tomorrow" in Control Center, so it isn't
/// part of Restore Original Settings.
@MainActor
final class NightShift: SystemSetting {
    let id = "nightShift"
    let title = "Night Shift"
    let symbol = "sunset"
    let restorable = false

    private typealias SupportsFn = @convention(c) (AnyClass, Selector) -> Bool
    private typealias GetStatusFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    private typealias SetEnabledFn = @convention(c) (AnyObject, Selector, Bool) -> Bool
    private typealias SetBlockFn = @convention(c) (AnyObject, Selector, @escaping @convention(block) () -> Void) -> Void

    private let client: NSObject?

    init() {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type,
              let supports = Self.classMethod(cls, "supportsBlueLightReduction", SupportsFn.self),
              supports.fn(cls, supports.sel),
              Self.method(cls, "getBlueLightStatus:", GetStatusFn.self) != nil,
              Self.method(cls, "setEnabled:", SetEnabledFn.self) != nil
        else {
            client = nil
            return
        }
        client = cls.init()
    }

    func read() -> Reading {
        guard let status = status() else {
            return Reading(state: .unavailable("Not available on this Mac"))
        }
        return Reading(state: status.enabled ? .on : .off, detail: status.scheduleDescription)
    }

    func write(_ on: Bool) async throws {
        guard let client, let set = Self.method(type(of: client), "setEnabled:", SetEnabledFn.self),
              set.fn(client, set.sel, on)
        else { throw SwitchboardError.failed("macOS didn't accept the Night Shift change.") }
    }

    func startObserving(_ changed: @escaping @MainActor () -> Void) {
        guard let client, let setBlock = Self.method(type(of: client), "setStatusNotificationBlock:", SetBlockFn.self)
        else { return }
        setBlock.fn(client, setBlock.sel) {
            Task { @MainActor in changed() }
        }
    }

    // MARK: Status

    /// The parts of CoreBrightness's StatusData struct that Switchboard uses:
    /// { BOOL active; BOOL enabled; BOOL sunSchedulePermitted; int mode;
    ///   { {int hour, minute} from, to } schedule; uint64 disableFlags; BOOL available }
    /// (40 bytes on macOS 27.)
    private struct Status {
        var enabled: Bool
        var mode: Int32  // 0 off, 1 sunset to sunrise, 2 custom
        var from: (hour: Int32, minute: Int32)
        var to: (hour: Int32, minute: Int32)

        var scheduleDescription: String? {
            switch mode {
            case 1: return "Scheduled sunset to sunrise"
            case 2: return "Scheduled \(Self.time(from)) to \(Self.time(to))"
            default: return nil
            }
        }

        private static func time(_ t: (hour: Int32, minute: Int32)) -> String {
            var components = DateComponents()
            components.hour = Int(t.hour)
            components.minute = Int(t.minute)
            guard let date = Calendar.current.date(from: components) else { return "\(t.hour):\(t.minute)" }
            return date.formatted(date: .omitted, time: .shortened)
        }
    }

    private func status() -> Status? {
        guard let client, let get = Self.method(type(of: client), "getBlueLightStatus:", GetStatusFn.self) else { return nil }
        // Generous and zeroed, in case a future macOS makes the struct bigger.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 256, alignment: 16)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: 256)
        guard get.fn(client, get.sel, buffer) else { return nil }
        return Status(
            enabled: buffer.load(fromByteOffset: 1, as: Bool.self),
            mode: buffer.load(fromByteOffset: 4, as: Int32.self),
            from: (buffer.load(fromByteOffset: 8, as: Int32.self), buffer.load(fromByteOffset: 12, as: Int32.self)),
            to: (buffer.load(fromByteOffset: 16, as: Int32.self), buffer.load(fromByteOffset: 20, as: Int32.self))
        )
    }

    // MARK: Objective-C calls

    private static func method<F>(_ cls: AnyClass, _ name: String, _: F.Type) -> (sel: Selector, fn: F)? {
        let sel = NSSelectorFromString(name)
        guard let m = class_getInstanceMethod(cls, sel) else { return nil }
        return (sel, unsafeBitCast(method_getImplementation(m), to: F.self))
    }

    private static func classMethod<F>(_ cls: AnyClass, _ name: String, _: F.Type) -> (sel: Selector, fn: F)? {
        let sel = NSSelectorFromString(name)
        guard let m = class_getClassMethod(cls, sel) else { return nil }
        return (sel, unsafeBitCast(method_getImplementation(m), to: F.self))
    }
}

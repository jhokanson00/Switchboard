import Darwin
import Foundation
import IOKit
import Observation

/// CPU and GPU load for the top of the panel. It samples only while the panel is open
/// (every 2 seconds) and does nothing otherwise.
@MainActor
@Observable
final class SystemMonitor {
    /// 0...1, or nil until the first reading (or when the Mac doesn't report it).
    private(set) var cpu: Double?
    private(set) var gpu: Double?

    private var sampling: Task<Void, Never>?
    private var lastTicks: CPUTicks?

    func start() {
        guard sampling == nil else { return }
        lastTicks = CPUTicks.now()
        gpu = Self.gpuUtilization()
        sampling = Task { [weak self] in
            // A quick first reading, then a steady one.
            var interval = Duration.milliseconds(500)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.sample()
                interval = .seconds(2)
            }
        }
    }

    func stop() {
        sampling?.cancel()
        sampling = nil
    }

    private func sample() {
        if let now = CPUTicks.now() {
            if let last = lastTicks { cpu = now.usage(since: last) }
            lastTicks = now
        }
        gpu = Self.gpuUtilization()
    }

    /// The busiest GPU's "Device Utilization %", the figure Activity Monitor's GPU
    /// History uses. Read from the IORegistry; no special permission needed.
    private static func gpuUtilization() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var busiest: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let percent = stats["Device Utilization %"] as? NSNumber {
                busiest = max(busiest ?? 0, percent.doubleValue / 100)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return busiest
    }
}

/// Cumulative CPU time across all cores, in ticks.
private struct CPUTicks {
    var busy: UInt64
    var total: UInt64

    static func now() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    func usage(since earlier: CPUTicks) -> Double? {
        guard total > earlier.total else { return nil }
        return Double(busy &- earlier.busy) / Double(total - earlier.total)
    }
}

import AppKit
import Observation

/// Removable drives for "Eject": USB sticks, SD cards, disk images and network volumes.
/// External hard disks are left alone, since getting one back means unplugging it. The
/// list follows macOS's mount and unmount announcements rather than checking.
@MainActor
@Observable
final class DriveEjector {
    struct Drive: Equatable {
        let name: String
        let url: URL
    }

    private(set) var drives: [Drive] = []
    private(set) var isEjecting = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey, .volumeIsInternalKey,
            .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let found = urls.compactMap { url -> Drive? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsRootFileSystem != true, values.volumeIsBrowsable != false
            else { return nil }
            // Hard disks, internal or external, report neither ejectable nor removable.
            let removable = values.volumeIsEjectable == true || values.volumeIsRemovable == true
                || values.volumeIsLocal == false
            return removable ? Drive(name: values.volumeName ?? url.lastPathComponent, url: url) : nil
        }
        if found != drives { drives = found }
    }

    /// Ejects every drive, one at a time. Returns what couldn't be ejected and why.
    func ejectAll() async -> [String] {
        guard !isEjecting else { return [] }
        isEjecting = true
        defer {
            isEjecting = false
            refresh()
        }
        var failures: [String] = []
        for drive in drives {
            do {
                try await FileManager.default.unmountVolume(at: drive.url, options: [.allPartitionsAndEjectDisk, .withoutUI])
            } catch {
                failures.append(Self.describe(error, drive: drive))
            }
        }
        return failures
    }

    /// "Seagate is in use by Final Cut Pro", when macOS says which app is holding it.
    private static func describe(_ error: Error, drive: Drive) -> String {
        let info = (error as NSError).userInfo
        if let pid = (info[NSFileManagerUnmountDissentingProcessIdentifierErrorKey] as? NSNumber)?.int32Value {
            let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "another process"
            return "\(drive.name) is in use by \(app)"
        }
        return "\(drive.name) couldn't be ejected"
    }
}

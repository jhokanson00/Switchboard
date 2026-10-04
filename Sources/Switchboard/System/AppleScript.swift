import Foundation

/// Runs AppleScript off the main thread, one script at a time. NSAppleScript isn't
/// thread-safe, so every script goes through the same serial queue.
enum AppleScript {
    private static let queue = DispatchQueue(label: "com.jacobhokanson.Switchboard.applescript")

    /// `timeout` bounds how long each Apple Event may wait for a reply, so an app that
    /// hangs can't leave a toggle stuck.
    @discardableResult
    static func run(_ source: String, timeout: Int = 15) async throws -> NSAppleEventDescriptor {
        let wrapped = "with timeout of \(timeout) seconds\n\(source)\nend timeout"
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: wrapped) else {
                    continuation.resume(throwing: SwitchboardError.failed("Couldn't build the script."))
                    return
                }
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    continuation.resume(throwing: SwitchboardError(appleScriptError: errorInfo, source: source))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}

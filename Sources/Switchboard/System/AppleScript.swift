import Foundation

/// Runs AppleScript in its own short-lived `osascript` process, never inside Switchboard.
///
/// In-process AppleScript (NSAppleScript) holds on to its connection to an app, and after
/// Finder restarts it could wait forever on the Finder that quit, past its own timeout,
/// blocking every script after it. A separate process starts fresh each time, and one
/// that hangs is simply stopped. macOS still attributes the Apple Events to Switchboard,
/// so the Automation permissions are the same.
enum AppleScript {
    /// Runs `source` and returns what it returns, as text.
    /// - Parameter timeout: How long each Apple Event may wait for a reply. The process
    ///   is stopped if it's still running a few seconds after that.
    @discardableResult
    static func run(_ source: String, timeout: Int = 15) async throws -> String {
        let script = "with timeout of \(timeout) seconds\n\(source)\nend timeout"
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = script.components(separatedBy: "\n").flatMap { ["-e", $0] }
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors

            let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
            process.terminationHandler = { finished in
                stop.cancel()
                let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let problem = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if finished.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: SwitchboardError.timedOut)
                } else if finished.terminationStatus != 0 {
                    continuation.resume(throwing: SwitchboardError(osascriptError: problem, source: source))
                } else {
                    continuation.resume(returning: text)
                }
            }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout + 5), execute: stop)
            } catch {
                continuation.resume(throwing: SwitchboardError.failed("Couldn't run AppleScript: \(error.localizedDescription)"))
            }
        }
    }
}

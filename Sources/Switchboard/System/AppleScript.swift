import Foundation

/// Runs AppleScript in its own short-lived `osascript` process, never inside Switchboard.
///
/// In-process AppleScript (NSAppleScript) holds on to its connection to an app, and after
/// Finder restarts it could wait forever on the Finder that quit, past its own timeout,
/// blocking every script after it. A separate process starts fresh each time, and one
/// that hangs is simply stopped. macOS still attributes the Apple Events to Switchboard,
/// so the Automation permissions are the same. The script goes in on standard input, not
/// the command line, which any process can read (it can contain folder paths).
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
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.standardInput = input
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
            } catch {
                continuation.resume(throwing: SwitchboardError.failed("Couldn't run AppleScript: \(error.localizedDescription)"))
                return
            }
            // Small enough to fit in the pipe, so writing doesn't wait for osascript. If
            // osascript is already gone, the write fails instead of raising SIGPIPE, which
            // would quit Switchboard; the termination handler then reports it.
            let writer = input.fileHandleForWriting
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            do {
                try writer.write(contentsOf: Data(script.utf8))
                try writer.close()
            } catch {
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout + 5), execute: stop)
        }
    }
}

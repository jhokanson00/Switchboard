import Foundation

enum SwitchboardError: LocalizedError, Equatable {
    /// macOS refused an Apple Event: the Automation permission is off for that app.
    case automationDenied(app: String)
    case bluetoothDenied
    case timedOut
    case failed(String)

    /// From osascript's error output, e.g.
    /// "0:30: execution error: Not authorized to send Apple events to Finder. (-1743)".
    init(osascriptError output: String, source: String) {
        var message = output
        if let range = message.range(of: "execution error: ") { message = String(message[range.upperBound...]) }
        var number = 0
        if let match = message.range(of: #"\((-?\d+)\)\s*$"#, options: .regularExpression) {
            number = Int(message[match].trimmingCharacters(in: CharacterSet(charactersIn: "() \n"))) ?? 0
            message = String(message[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        switch number {
        case -1743:  // errAEEventNotPermitted
            self = .automationDenied(app: source.contains("\"Finder\"") ? "Finder" : "System Events")
        case -1712:  // errAETimeout
            self = .timedOut
        default:
            self = .failed(message.isEmpty ? "AppleScript error \(number)." : message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .automationDenied(let app):
            "Switchboard isn't allowed to control \(app). Turn it on in Privacy & Security → Automation."
        case .bluetoothDenied:
            "Switchboard isn't allowed to use Bluetooth. Turn it on in Privacy & Security → Bluetooth."
        case .timedOut:
            "macOS didn't respond in time. Try again."
        case .failed(let message):
            message
        }
    }

    /// The System Settings pane that fixes this, if there is one.
    var settingsURL: URL? {
        switch self {
        case .automationDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .bluetoothDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        default:
            nil
        }
    }
}

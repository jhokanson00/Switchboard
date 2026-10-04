import Foundation

enum SwitchboardError: LocalizedError, Equatable {
    /// macOS refused an Apple Event: the Automation permission is off for that app.
    case automationDenied(app: String)
    case bluetoothDenied
    case timedOut
    case failed(String)

    init(appleScriptError info: NSDictionary, source: String) {
        let number = info[NSAppleScript.errorNumber] as? Int ?? 0
        switch number {
        case -1743:  // errAEEventNotPermitted
            self = .automationDenied(app: source.contains("\"Finder\"") ? "Finder" : "System Events")
        case -1712:  // errAETimeout
            self = .timedOut
        default:
            self = .failed(info[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number).")
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

import AppKit

@MainActor
enum Alerts {
    /// A standard confirmation. Switchboard has no windows, so it comes forward first.
    static func confirm(title: String, message: String, confirm: String, destructive: Bool = true) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm).hasDestructiveAction = destructive
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

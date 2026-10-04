import AppKit

/// SwiftUI's MenuBarExtra has no way to open its panel from code. Its status item is an
/// ordinary button in a status bar window of this app, so clicking that button does it.
@MainActor
enum StatusItemPanel {
    static func open() {
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            if let button = firstButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func firstButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let button = firstButton(in: subview) { return button }
        }
        return nil
    }
}

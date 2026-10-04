import AppKit
import SwiftUI

/// A brief confirmation near the bottom of the screen, like the volume indicator, for
/// changes made with a keyboard shortcut while the panel is closed. Mute Microphone
/// would otherwise give no sign it worked.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var hide: Task<Void, Never>?

    static func show(symbol: String, title: String, detail: String) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: HUDView(symbol: symbol, title: title, detail: detail))
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 120))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hide?.cancel()
        hide = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 0 }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

private struct HUDView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .frame(height: 40)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(minWidth: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

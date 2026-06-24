import AppKit
import SwiftUI

/// Transparent view that captures the hosting NSWindow once it is available.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op: window is captured once in makeNSView.
        // Calling onWindow here on every SwiftUI update creates a feedback loop:
        // setContentSize → AppKit layout → SwiftUI re-render → updateNSView → setContentSize → …
    }
}

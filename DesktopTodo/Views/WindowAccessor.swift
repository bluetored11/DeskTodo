import AppKit
import SwiftUI

/// Transparent view that captures the hosting NSWindow once it is available.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}

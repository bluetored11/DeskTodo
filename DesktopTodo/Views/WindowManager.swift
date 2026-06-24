import AppKit

struct WindowManager {
    /// 紧凑模式（Pin）窗口尺寸
    static let compactSize = NSSize(width: 320, height: 480)
    /// 普通模式最小尺寸
    static let normalMinSize = NSSize(width: 600, height: 400)

    /// 根据 isPinned 状态调整窗口层级与尺寸
    @MainActor
    static func apply(isPinned: Bool, window: NSWindow? = nil) {
        guard let window = window ?? NSApp.mainWindow else { return }
        if isPinned {
            window.level = .floating
            window.minSize = NSSize(width: 320, height: 300)
            window.setContentSize(compactSize)
        } else {
            window.level = .normal
            window.minSize = normalMinSize
            window.setContentSize(normalMinSize)
        }
    }
}

import SwiftUI
import AppKit

@MainActor
class UnfinishedMilestonesWindowManager: NSObject, NSWindowDelegate {
    static let shared = UnfinishedMilestonesWindowManager()
    
    private var window: NSWindow?
    private weak var store: ProjectStore?
    
    var isWindowVisible: Bool { window?.isVisible ?? false }
    
    func show(store: ProjectStore, retryCount: Int = 0) {
        self.store = store
        
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        // Ensure the main window exists before presenting the milestone window.
        // If SwiftUI hasn't mounted the main window yet, defer presentation slightly
        // so that SwiftUI's WindowGroup is not preempted or suppressed by macOS.
        let hasMainWindow = NSApp.windows.contains {
            $0.canBecomeMain &&
            $0.identifier?.rawValue != "UnfinishedMilestonesWindow" &&
            $0.identifier?.rawValue != "TaskDetailWindow" &&
            $0.level != .floating &&
            $0.isVisible
        }
        
        if !hasMainWindow && retryCount < 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.show(store: store, retryCount: retryCount + 1)
            }
            return
        }
        
        let targetSize = NSSize(width: 580, height: 570)
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: targetSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.identifier = NSUserInterfaceItemIdentifier("UnfinishedMilestonesWindow")
        newWindow.minSize = NSSize(width: 460, height: 360)
        newWindow.setContentSize(targetSize)
        newWindow.title = "미완료 마일스톤 목록"
        newWindow.center()
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.delegate = self
        
        newWindow.contentView = NSHostingView(
            rootView: UnfinishedMilestonesView(
                store: store,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }
    
    func close() {
        window?.close()
        window = nil
    }
    
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

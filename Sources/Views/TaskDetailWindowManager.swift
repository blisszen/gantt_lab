import SwiftUI
import AppKit

@MainActor
class TaskDetailWindowManager: NSObject, NSWindowDelegate {
    static let shared = TaskDetailWindowManager()
    
    private var detailWindow: NSWindow?
    private weak var store: ProjectStore?
    
    var window: NSWindow? { detailWindow }
    var isWindowVisible: Bool { detailWindow?.isVisible ?? false }
    
    func updateTitle(_ title: String, isMilestone: Bool = false) {
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = isMilestone ? "마일스톤 세부 설정" : "작업 세부 설정"
        detailWindow?.title = "\(prefix) - \(displayTitle.isEmpty ? "새 작업" : displayTitle)"
    }
    
    func show(taskId: UUID, store: ProjectStore, isConvertMilestoneDisabled: Bool = false) {
        if store.editingTaskId != nil {
            store.commitInlineEditing()
        }
        self.store = store
        guard let task = store.findTask(id: taskId) else { return }
        let prefix = task.isMilestone ? "마일스톤 세부 설정" : "작업 세부 설정"
        
        if let existing = detailWindow {
            existing.title = "\(prefix) - \(task.title)"
            existing.contentView = NSHostingView(
                rootView: TaskDetailSheet(
                    store: store,
                    taskId: taskId,
                    isConvertMilestoneDisabled: isConvertMilestoneDisabled,
                    onClose: { [weak self] in
                        self?.close()
                    }
                )
            )
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 780, height: 560)
        window.title = "\(prefix) - \(task.title)"
        window.center()
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating // Floats over main window so user can move it around while looking at the chart!
        window.delegate = self
        
        window.contentView = NSHostingView(
            rootView: TaskDetailSheet(
                store: store,
                taskId: taskId,
                isConvertMilestoneDisabled: isConvertMilestoneDisabled,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
        
        self.detailWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        detailWindow?.close()
        detailWindow = nil
        store?.detailTask = nil
    }
    
    func windowWillClose(_ notification: Notification) {
        detailWindow = nil
        store?.detailTask = nil
    }
}

import SwiftUI
import AppKit

// MARK: - Current Version (Build Date & Build Number)
var currentVersion: String {
    let info = Bundle.main.infoDictionary
    let shortVer = info?["CFBundleShortVersionString"] as? String
    let bundleVer = info?["CFBundleVersion"] as? String
    
    if let shortVer = shortVer, !shortVer.isEmpty, shortVer != "0.01" {
        // 이미 "YYYY.MM.DD (N)" 형식으로 구성되어 있는 경우 그대로 반환
        if shortVer.contains("(") && shortVer.contains(")") {
            return shortVer
        }
        // CFBundleVersion에 빌드 번호가 분리되어 있는 경우 조합
        if let build = bundleVer, !build.isEmpty, build != shortVer {
            return "\(shortVer) (\(build))"
        }
        return shortVer
    }
    
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy.MM.dd"
    let dateStr: String
    if let execPath = Bundle.main.executablePath,
       let attrs = try? FileManager.default.attributesOfItem(atPath: execPath),
       let date = attrs[.modificationDate] as? Date {
        dateStr = formatter.string(from: date)
    } else {
        dateStr = formatter.string(from: Date())
    }
    
    if let build = bundleVer, !build.isEmpty {
        return "\(dateStr) (\(build))"
    }
    return "\(dateStr) (1)"
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var store: ProjectStore?
    
    @MainActor func isAuxiliaryWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == "UnfinishedMilestonesWindow" ||
           window.identifier?.rawValue == "TaskDetailWindow" ||
           window.level == .floating ||
           window.title.contains("미완료 마일스톤") ||
           window.title.contains("작업 세부 설정") {
            return true
        }
        return false
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Set App Icon from project.png or Bundle icon
        if let bundleIcon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = bundleIcon
        } else if let projectPng = NSImage(contentsOfFile: "project.png") {
            NSApplication.shared.applicationIconImage = projectPng
        }
        
        // Ensure main window is displayed and configured
        DispatchQueue.main.async { [weak self] in
            self?.ensureMainWindowPresented()
            
            // Intercept standard About menu item to show our unified About sheet
            if let appMenu = NSApp.mainMenu?.items.first?.submenu {
                for item in appMenu.items {
                    if item.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)) ||
                       item.title.localizedCaseInsensitiveContains("About") ||
                       item.title.localizedCaseInsensitiveContains("정보") {
                        item.target = self
                        item.action = #selector(self?.showAboutSheetFromMenu)
                    }
                }
            }
            
            // Ensure "View" (보기) menu has "미완료 마일스톤 보기"
            if let mainMenu = NSApp.mainMenu {
                for item in mainMenu.items {
                    if let submenu = item.submenu,
                       item.title.localizedCaseInsensitiveContains("View") ||
                       item.title.localizedCaseInsensitiveContains("보기") {
                        let alreadyHas = submenu.items.contains { $0.title.contains("미완료 마일스톤") }
                        if !alreadyHas {
                            submenu.addItem(NSMenuItem.separator())
                            let milestoneItem = NSMenuItem(
                                title: "미완료 마일스톤 보기",
                                action: #selector(self?.showUnfinishedMilestonesFromMenu(_:)),
                                keyEquivalent: "m"
                            )
                            milestoneItem.keyEquivalentModifierMask = [.command, .shift]
                            milestoneItem.target = self
                            submenu.addItem(milestoneItem)
                        }
                    }
                }
            }
        }
        
        // Safety monitor for mouse up to clean up any stuck drag states
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            if let store = self?.store, store.draggedTaskId != nil {
                // Slight delay so that performDrop can finish processing if dropped on valid target
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    store.cleanupDragState()
                }
            }
            return event
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.store?.cleanupDragState()
            }
        }
        
        // Monitor key events
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let store = self.store else { return event }
            let isCmd = event.modifierFlags.contains(.command)
            let isShift = event.modifierFlags.contains(.shift)
            let isOpt = event.modifierFlags.contains(.option)
            let isCtrl = event.modifierFlags.contains(.control)
            let currentWindow = event.window ?? NSApp.keyWindow
            
            // Check if text editing is active (in task tree inline editor, task detail settings text fields, or any text editor)
            let isEditingText = TextEditingHelper.isEditingText(store: store, in: currentWindow)
            
            if isEditingText {
                // If Cmd + arrow keys pressed during text editing:
                // Strictly use Cmd input for text cursor navigation/selection and NEVER move tasks in the tree!
                if isCmd && !isOpt && !isCtrl {
                    if TextEditingHelper.handleTextCursorMovement(event: event, in: currentWindow) {
                        return nil // Consumed by text navigation
                    }
                    // Safety: Arrow keys with Cmd during text editing must NEVER fall through to tree manipulation!
                    if event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 126 {
                        return nil
                    }
                }
                
                // Cmd-X during text editing: Pass through to text field for Cut (do not quit app!)
                if isCmd && !isShift && event.charactersIgnoringModifiers == "x" {
                    return event
                }
                
                // Cmd-Z during text editing: Undo text changes in the active text field/editor, NOT project tasks!
                if isCmd && !isShift && (event.keyCode == 6 || event.charactersIgnoringModifiers == "z") {
                    if let tv = TextEditingHelper.activeEditableTextView(in: currentWindow),
                       let um = tv.undoManager, um.canUndo {
                        um.undo()
                        return nil
                    }
                    return event
                }
                
                // Return, Shift+Return, Delete, typing characters: let the text field handle them
                return event
            }
            
            // ==========================================
            // Outside text editing: standard tree/task manipulation
            // ==========================================
            
            // 1. Check for Cmd + Right Arrow (Keycode 124): Indent to child level
            if isCmd && !isShift && !isOpt && !isCtrl && event.keyCode == 124 {
                DispatchQueue.main.async {
                    store.indentSelectedTask()
                }
                return nil
            }
            
            // 2. Check for Cmd + Left Arrow (Keycode 123): Outdent to parent level
            if isCmd && !isShift && !isOpt && !isCtrl && event.keyCode == 123 {
                DispatchQueue.main.async {
                    store.outdentSelectedTask()
                }
                return nil
            }
            
            // 2-1. Check for Cmd + Up Arrow (Keycode 126): Move task up in tree hierarchy
            if isCmd && !isShift && !isOpt && !isCtrl && event.keyCode == 126 {
                DispatchQueue.main.async {
                    store.moveSelectedTaskUpInTree()
                }
                return nil
            }
            
            // 2-2. Check for Cmd + Down Arrow (Keycode 125): Move task down in tree hierarchy
            if isCmd && !isShift && !isOpt && !isCtrl && event.keyCode == 125 {
                DispatchQueue.main.async {
                    store.moveSelectedTaskDownInTree()
                }
                return nil
            }
            
            // 3. Check for Cmd-X (and not Shift): Close/Quit confirmation if not in text editing
            if isCmd && !isShift && event.charactersIgnoringModifiers == "x" {
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
                return nil
            }
            
            // 4. Check for Shift + Return (KeyCode 36 or 76): Add same-level sibling right below selected task
            if isShift && !isCmd && (event.keyCode == 36 || event.keyCode == 76) {
                if let selected = store.selectedTaskId {
                    DispatchQueue.main.async {
                        store.commitAndCreateNextTask(currentId: selected)
                    }
                    return nil
                }
            }
            
            // 5. Check for Return (without Shift/Cmd) on selected task: Start editing title
            if !isShift && !isCmd && (event.keyCode == 36 || event.keyCode == 76) {
                if let selected = store.selectedTaskId {
                    DispatchQueue.main.async {
                        store.startEditing(taskId: selected)
                    }
                    return nil
                }
            }
            
            // 6. Check for Delete / Forward Delete (Keycode 51 or 117): Delete selected task
            if !isCmd && !isShift && (event.keyCode == 51 || event.keyCode == 117) {
                if store.selectedTaskId != nil {
                    DispatchQueue.main.async {
                        store.deleteSelectedTask()
                    }
                    return nil
                }
            }
            
            // 7. Check for Cmd-Z: Undo last action (up to 10 steps)
            if isCmd && !isShift && (event.keyCode == 6 || event.charactersIgnoringModifiers == "z") {
                DispatchQueue.main.async {
                    store.undo()
                }
                return nil
            }
            
            return event
        }
    }
    
    @MainActor func ensureMainWindowPresented() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        var found = false
        for window in NSApp.windows {
            if window.canBecomeMain && !isAuxiliaryWindow(window) {
                found = true
                window.delegate = self
                restoreWindowState(for: window)
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
        
        if !found {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                for window in NSApp.windows {
                    if window.canBecomeMain && !self.isAuxiliaryWindow(window) {
                        window.delegate = self
                        self.restoreWindowState(for: window)
                        if window.isMiniaturized {
                            window.deminiaturize(nil)
                        }
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            }
        }
    }
    
    // Handle clicking Dock icon or reopening app when windows might be closed or minimized
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.ensureMainWindowPresented()
        }
        return true
    }
    
    // Terminate app when the main window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    // Handle opening .ganttlab files from Finder (double click or Open With)
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        store?.loadProject(from: url)
        return true
    }
    
    // MARK: - Window & Layout Autosave (Stored in Mac Cache/UserDefaults)
    private static let keyWindowWidth = "GanttLab_WindowWidth"
    private static let keyWindowHeight = "GanttLab_WindowHeight"
    private static let keyWindowX = "GanttLab_WindowX"
    private static let keyWindowY = "GanttLab_WindowY"
    private static let keyWindowAutosaveName = "GanttLabMainWindow"
    
    @MainActor func saveWindowState() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain && !isAuxiliaryWindow($0) }) else { return }
        window.saveFrame(usingName: Self.keyWindowAutosaveName)
        let frame = window.frame
        let defaults = UserDefaults.standard
        defaults.set(Double(frame.size.width), forKey: Self.keyWindowWidth)
        defaults.set(Double(frame.size.height), forKey: Self.keyWindowHeight)
        defaults.set(Double(frame.origin.x), forKey: Self.keyWindowX)
        defaults.set(Double(frame.origin.y), forKey: Self.keyWindowY)
        
        store?.saveLayoutSettings()
    }
    
    @MainActor func restoreWindowState(for window: NSWindow) {
        window.setFrameAutosaveName(Self.keyWindowAutosaveName)
        
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.keyWindowWidth) != nil {
            let width = defaults.double(forKey: Self.keyWindowWidth)
            let height = defaults.double(forKey: Self.keyWindowHeight)
            let x = defaults.double(forKey: Self.keyWindowX)
            let y = defaults.double(forKey: Self.keyWindowY)
            
            if width >= 800 && height >= 500 {
                let rect = NSRect(x: x, y: y, width: width, height: height)
                let visibleScreens = NSScreen.screens.compactMap { $0.visibleFrame }
                let isOnScreen = visibleScreens.contains { $0.intersects(rect) }
                if isOnScreen {
                    window.setFrame(rect, display: true)
                } else {
                    window.setContentSize(NSSize(width: width, height: height))
                    window.center()
                }
            }
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.saveWindowState()
        }
    }
    
    func windowDidMove(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.saveWindowState()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        saveWindowState()
    }
    
    // Intercept Cmd-Q, App Quit menu, Dock Quit, Cmd-X, etc.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        saveWindowState()
        guard let store = store else { return .terminateNow }
        if store.confirmSaveBeforeClosing() {
            store.isDirty = false
            return .terminateNow
        } else {
            return .terminateCancel
        }
    }
    
    // Intercept Window close ('X' button or Cmd-W)
    @MainActor func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isAuxiliaryWindow(sender) {
            return true
        }
        saveWindowState()
        guard let store = store else { return true }
        if store.confirmSaveBeforeClosing() {
            store.isDirty = false
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return true
        } else {
            return false
        }
    }
    
    // Intercept standard About menu items to present the unified About sheet
    @MainActor @objc func showAboutSheetFromMenu(_ sender: Any?) {
        self.store?.showAboutView = true
    }
    
    @MainActor @objc func showUnfinishedMilestonesFromMenu(_ sender: Any?) {
        if let store = self.store {
            UnfinishedMilestonesWindowManager.shared.show(store: store)
        }
    }
    
    @MainActor @objc func orderFrontStandardAboutPanel(_ sender: Any?) {
        self.store?.showAboutView = true
    }
}

@main
struct GanttLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ProjectStore()
    
    var body: some Scene {
        WindowGroup {
            MainView(store: store)
                .frame(minWidth: 960, idealWidth: 1300, minHeight: 600, idealHeight: 820)
                .navigationTitle(store.windowTitle)
                .onAppear {
                    appDelegate.store = store
                    DispatchQueue.main.async {
                        appDelegate.ensureMainWindowPresented()
                        // Align Gantt chart so Today is placed at 2 days from the left edge (left edge is Today - 2 days)
                        store.scrollToToday(offsetDaysFromLeft: 2)
                        
                        // Safely trigger unfinished milestones window only after the main window is guaranteed to be presented and visible!
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            store.checkAndShowUnfinishedMilestones()
                        }
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            // macOS 앱 메뉴(Gantt Lab)의 About 항목 대체
            CommandGroup(replacing: .appInfo) {
                Button("About Gantt Lab") {
                    store.showAboutView = true
                }
            }
            
            // "파일" 메뉴 구성
            CommandGroup(replacing: .newItem) {
                Button("새 프로젝트") {
                    store.requestNewProject()
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("기존 프로젝트 읽기...") {
                    store.openProject()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("저장하기") {
                    store.saveProject()
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button("다른이름으로 저장...") {
                    store.saveProjectAs()
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])
                
                Divider()
                
                Button("작업자 별 할일 저장...") {
                    store.showExportAssigneeTasksSheet = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                
                Button("모든 작업자별 할일 저장...") {
                    store.exportAllAssigneesTasks()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift, .option])
            }
            
            // "편집" 메뉴의 실행 취소 (Undo) 구성
            CommandGroup(replacing: .undoRedo) {
                Button("실행 취소") {
                    store.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo || !store.isTaskTreeManipulationAllowed)
            }
            
            // "작업" 메뉴 구성 (들여쓰기, 내어쓰기, 상하 이동 등)
            CommandMenu("작업") {
                Button("하위 레벨로 들여쓰기") {
                    store.indentSelectedTask()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!store.isTaskTreeManipulationAllowed)
                
                Button("상위 레벨로 내어쓰기") {
                    store.outdentSelectedTask()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!store.isTaskTreeManipulationAllowed)
                
                Divider()
                
                Button("위로 이동") {
                    store.moveSelectedTaskUpInTree()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!store.isTaskTreeManipulationAllowed)
                
                Button("아래로 이동") {
                    store.moveSelectedTaskDownInTree()
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!store.isTaskTreeManipulationAllowed)
                
                Divider()
                
                Button("새 작업 추가") {
                    let newId = store.createNewTask(after: store.selectedTaskId, asChild: false)
                    store.editingTaskId = newId
                }
                .disabled(store.editingTaskId != nil)
                
                Button("하위 작업 추가") {
                    if let selected = store.selectedTaskId {
                        let newId = store.createNewTask(after: selected, asChild: true)
                        store.editingTaskId = newId
                    }
                }
                .disabled(!store.isTaskTreeManipulationAllowed)
                
                Divider()
                
                Button("선택한 작업 삭제") {
                    store.deleteSelectedTask()
                }
                .disabled(!store.isTaskTreeManipulationAllowed)
            }
            
            // "View" (보기) 메뉴 구성
            CommandGroup(after: .toolbar) {
                Divider()
                
                Button("미완료 마일스톤 보기") {
                    UnfinishedMilestonesWindowManager.shared.show(store: store)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            
            // macOS 시스템 Help 메뉴 하위에 "소개" 메뉴 항목 배치
            CommandGroup(replacing: .help) {
                Button("소개") {
                    store.showAboutView = true
                }
            }
            
            // 앱 종료 메뉴 - Cmd-Q / Cmd-X 지원
            CommandGroup(replacing: .appTermination) {
                Button("Gantt Lab 종료") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

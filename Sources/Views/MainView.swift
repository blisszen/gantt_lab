import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var store: ProjectStore
    
    // Initial split fraction (1:3 => left ~ 320pt)
    @State private var leftWidth: CGFloat = 340
    @State private var bottomHeight: CGFloat = 180
    
    var body: some View {
        VStack(spacing: 0) {
            // Upper Area: Left Tree : Right Gantt Chart (Width synced with WorkloadView)
            HStack(spacing: 0) {
                LeftTreeView(store: store)
                    .frame(width: store.leftPaneWidth)
                    .zIndex(10)
                
                VerticalSplitDivider(paneWidth: $store.leftPaneWidth)
                    .zIndex(11)
                
                GanttTimelineView(store: store)
                    .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Horizontal Split Divider between Gantt Chart and Workload
            HorizontalSplitDivider(paneHeight: $store.bottomPaneHeight)
                .zIndex(12)
            
            // Lower Area: Workload View (Resizable height via HorizontalSplitDivider, restored across app sessions)
            WorkloadView(store: store)
                .frame(height: store.bottomPaneHeight)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // New Task Button
                Button(action: {
                    let newId = store.createNewTask(after: store.selectedTaskId, asChild: false)
                    store.editingTaskId = newId
                }) {
                    Label("작업 추가", systemImage: "plus")
                }
                .help("새 작업 추가 (Shift-Enter로도 연속 추가 가능)")
                
                // New Subtask Button
                Button(action: {
                    if let selected = store.selectedTaskId {
                        let newId = store.createNewTask(after: selected, asChild: true)
                        store.editingTaskId = newId
                    }
                }) {
                    Label("하위 작업 추가", systemImage: "arrow.turn.down.right")
                }
                .disabled(store.selectedTaskId == nil)
                .help("선택한 작업의 하위 작업 추가")
                
                // Delete Task Button
                Button(action: {
                    store.deleteSelectedTask()
                }) {
                    Label("작업 삭제", systemImage: "trash")
                }
                .disabled(store.selectedTaskId == nil)
                .help("선택한 작업 및 하위 작업 삭제 (Del 키)")
                
                Divider()
                
                // Tree Indent / Outdent buttons
                Button(action: {
                    store.outdentSelectedTask()
                }) {
                    Label("상위 레벨로", systemImage: "arrow.left.to.line")
                }
                .disabled(store.selectedTaskId == nil)
                .help("작업을 상위 레벨로 이동 (단축키: ⌘←)")
                
                Button(action: {
                    store.indentSelectedTask()
                }) {
                    Label("하위 레벨로", systemImage: "arrow.right.to.line")
                }
                .disabled(store.selectedTaskId == nil)
                .help("작업을 하위 레벨로 이동 (단축키: ⌘→)")
                
                Divider()
                
                // Zoom Controls
                Button(action: {
                    withAnimation {
                        store.dayWidth = max(22.0, store.dayWidth - 6.0)
                    }
                }) {
                    Label("축소", systemImage: "minus.magnifyingglass")
                }
                .help("타임라인 축소")
                
                Button(action: {
                    withAnimation {
                        store.dayWidth = min(64.0, store.dayWidth + 6.0)
                    }
                }) {
                    Label("확대", systemImage: "plus.magnifyingglass")
                }
                .help("타임라인 확대")
                
                // Recalculate / Fit Timeline
                Button(action: {
                    withAnimation {
                        store.recalculateTimelineRange()
                    }
                }) {
                    Label("범위 맞춤", systemImage: "arrow.left.and.right.square")
                }
                .help("모든 작업이 보이도록 타임라인 맞춤")
                
                Divider()
                
                // Assignee Manager Global Button
                Button(action: {
                    store.assigneeManagerTaskId = store.selectedTaskId ?? store.flattenedRows.first?.id
                }) {
                    Label("작업자 관리", systemImage: "person.2.badge.gearshape")
                }
                .help("작업자 목록 및 사진 관리")
                
                Divider()
                
                // Unfinished Milestones Window Trigger
                Button(action: {
                    UnfinishedMilestonesWindowManager.shared.show(store: store)
                }) {
                    Label("미완료 마일스톤", systemImage: "flag.checkered")
                }
                .help("오늘 기준 미완료 마일스톤 목록 창 열기")
            }
        }
        // Movable Task Detail Window
        .onChange(of: store.detailTask) { _, newTask in
            if let task = newTask {
                TaskDetailWindowManager.shared.show(taskId: task.id, store: store)
            }
        }
        // Modal Sheet: Attachment Integrity Report
        .sheet(item: $store.attachmentReport) { report in
            AttachmentReportSheet(report: report) {
                store.attachmentReport = nil
            }
        }
        // Modal Sheet: Assignee Manager
        .sheet(isPresented: Binding(
            get: { store.assigneeManagerTaskId != nil },
            set: { if !$0 { store.assigneeManagerTaskId = nil } }
        )) {
            AssigneeManagerSheet(store: store, taskId: store.assigneeManagerTaskId)
        }
        // Modal Sheet: About App
        .sheet(isPresented: $store.showAboutView) {
            AboutSheet()
        }
        // Modal Sheet: Assignee Tasks Export
        .sheet(isPresented: $store.showExportAssigneeTasksSheet) {
            AssigneeExportSheet(store: store)
        }
        // Modal Sheet: All Assignees Tasks Export (ZIP)
        .sheet(isPresented: $store.showExportAllAssigneesSheet) {
            AllAssigneesExportSheet(store: store)
        }
        // Alert: Unsaved Changes before New Project
        .alert("저장되지 않은 변경사항", isPresented: $store.showUnsavedAlert) {
            Button("저장 후 새로 만들기") {
                store.saveProject()
                store.pendingNewProjectAction?()
                store.pendingNewProjectAction = nil
            }
            Button("저장하지 않고 새로 만들기", role: .destructive) {
                store.pendingNewProjectAction?()
                store.pendingNewProjectAction = nil
            }
            Button("취소", role: .cancel) {
                store.pendingNewProjectAction = nil
            }
        } message: {
            Text("현재 작업한 내용이 저장되지 않았습니다. 새 프로젝트를 생성하기 전에 저장하시겠습니까?")
        }
        .background(KeyDownHandler(store: store))
        .onOpenURL { url in
            store.loadProject(from: url)
        }
    }
}

// MARK: - Global Window Key Down Handler
struct KeyDownHandler: NSViewRepresentable {
    @ObservedObject var store: ProjectStore
    
    func makeNSView(context: Context) -> KeyHandlerNSView {
        let view = KeyHandlerNSView()
        view.store = store
        return view
    }
    
    func updateNSView(_ nsView: KeyHandlerNSView, context: Context) {
        nsView.store = store
    }
    
    class KeyHandlerNSView: NSView {
        var store: ProjectStore?
        private var monitor: Any?
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
        
        private func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, let win = self.window, event.window == win, let store = self.store else {
                    return event
                }
                
                // If user is currently editing text in any text field or text view:
                if TextEditingHelper.isEditingText(store: store, in: win) {
                    return event // Pass through to text field!
                }
                
                let isShift = event.modifierFlags.contains(.shift)
                let isCmd = event.modifierFlags.contains(.command)
                let isOpt = event.modifierFlags.contains(.option)
                let isCtrl = event.modifierFlags.contains(.control)
                
                // KeyCodes:
                // 126 = Up Arrow
                // 125 = Down Arrow
                // 123 = Left Arrow
                // 124 = Right Arrow
                
                switch event.keyCode {
                case 126: // Up Arrow
                    if !isShift && !isCmd && !isOpt && !isCtrl {
                        // Up: Move selection to previous task
                        store.selectPreviousTask()
                        return nil
                    }
                    
                case 125: // Down Arrow
                    if !isShift && !isCmd && !isOpt && !isCtrl {
                        // Down: Move selection to next task
                        store.selectNextTask()
                        return nil
                    }
                    
                case 123: // Left Arrow
                    if !isCmd && !isOpt && !isCtrl && !isShift {
                        // Left: Shift selected task bar -1 day
                        store.shiftSelectedTask(byDays: -1)
                        return nil
                    }
                    
                case 124: // Right Arrow
                    if !isCmd && !isOpt && !isCtrl && !isShift {
                        // Right: Shift selected task bar +1 day
                        store.shiftSelectedTask(byDays: 1)
                        return nil
                    }
                    
                default:
                    break
                }
                
                return event
            }
        }
        
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                stopMonitoring()
            }
        }
        
        private func stopMonitoring() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
        
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }
}

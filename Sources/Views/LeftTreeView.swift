import SwiftUI
import AppKit
import UniformTypeIdentifiers

// NSViewRepresentable that captures Shift+Enter and Normal Enter cleanly in macOS without triggering full-app re-renders on keystrokes
struct TreeInlineTextField: NSViewRepresentable {
    var initialText: String
    var onCommit: (String) -> Void
    var onShiftEnter: (String) -> Void
    var onCancel: () -> Void
    var onTextChanged: ((String) -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        textField.focusRingType = .none
        textField.stringValue = initialText
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.isAutomaticTextCompletionEnabled = false
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.textSubmitted)
        context.coordinator.textField = textField
        
        DispatchQueue.main.async {
            if let window = textField.window {
                window.makeFirstResponder(textField)
                textField.selectText(nil)
            }
        }
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if !context.coordinator.hasSetInitialFocus {
            context.coordinator.hasSetInitialFocus = true
            DispatchQueue.main.async {
                if let window = nsView.window {
                    window.makeFirstResponder(nsView)
                    nsView.selectText(nil)
                }
            }
        }
    }
    
    @MainActor
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TreeInlineTextField
        weak var textField: NSTextField?
        var hasSetInitialFocus = false
        private var hasCommitted = false
        private let mountTime: TimeInterval
        
        init(_ parent: TreeInlineTextField) {
            self.parent = parent
            self.mountTime = ProcessInfo.processInfo.systemUptime
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.onTextChanged?(tf.stringValue)
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            // Ignore any premature focus-out events within 0.3s of mounting to prevent immediate edit cancellation
            let elapsed = ProcessInfo.processInfo.systemUptime - mountTime
            guard elapsed > 0.3 else { return }
            
            guard !hasCommitted else { return }
            hasCommitted = true
            let finalValue = (obj.object as? NSTextField)?.stringValue ?? textField?.stringValue ?? ""
            parent.onCommit(finalValue)
        }
        
        @objc func textSubmitted() {
            guard !hasCommitted else { return }
            hasCommitted = true
            let finalValue = textField?.stringValue ?? ""
            parent.onCommit(finalValue)
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let event = NSApp.currentEvent
            let isShift = event?.modifierFlags.contains(.shift) ?? false
            let currentText = textView.string
            
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard !hasCommitted else { return true }
                hasCommitted = true
                if isShift {
                    // Shift + Enter: Commit and request next sibling task
                    parent.onShiftEnter(currentText)
                    return true
                } else {
                    // Regular Enter: Commit
                    parent.onCommit(currentText)
                    return true
                }
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                hasCommitted = true
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

// Full-height interactive column splitter between "작업트리" (Task Name) and "작업자" (Assignees)
struct TreeColumnSplitter: View {
    @ObservedObject var store: ProjectStore
    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false
    @State private var dragStartTreeWidth: CGFloat? = nil
    @State private var dragStartLeftPaneWidth: CGFloat? = nil
    
    var body: some View {
        ZStack {
            // Invisible wider hit-target area (16pt wide) for effortless grabbing
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 16)
                .contentShape(Rectangle())
            
            // Visual feedback line: subtle accent on hover, solid vibrant accent during drag
            Rectangle()
                .fill(isDragging ? Color.accentColor : (isHovering ? Color.accentColor.opacity(0.6) : Color.clear))
                .frame(width: isDragging ? 2.5 : 2)
        }
        .frame(width: 16)
        .frame(maxHeight: .infinity)
        .cursor(.resizeLeftRight)
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { val in
                    if dragStartTreeWidth == nil {
                        dragStartTreeWidth = store.treeNameWidth
                        dragStartLeftPaneWidth = store.leftPaneWidth
                        isDragging = true
                    }
                    guard let startTree = dragStartTreeWidth,
                          let startPane = dragStartLeftPaneWidth else { return }
                    
                    let delta = val.translation.width
                    let minTreeWidth: CGFloat = 110
                    let newTreeWidth = max(minTreeWidth, startTree + delta)
                    
                    store.treeNameWidth = newTreeWidth
                    
                    // Smoothly ensure Assignee column doesn't get squeezed below 100pt:
                    let minAssigneeWidth: CGFloat = 100
                    let attachmentWidth: CGFloat = 34
                    let completeWidth: CGFloat = 44
                    let dividersWidth: CGFloat = 3
                    let minRequiredPane = newTreeWidth + minAssigneeWidth + attachmentWidth + completeWidth + dividersWidth
                    
                    if minRequiredPane > store.leftPaneWidth {
                        store.leftPaneWidth = min(900, minRequiredPane)
                    } else if newTreeWidth < startTree && store.leftPaneWidth > startPane {
                        let targetPane = max(startPane, minRequiredPane)
                        store.leftPaneWidth = targetPane
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    dragStartTreeWidth = nil
                    dragStartLeftPaneWidth = nil
                }
        )
    }
}

struct LeftTreeView: View {
    @ObservedObject var store: ProjectStore
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("작업 트리")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 14)
                        .frame(width: store.treeNameWidth, alignment: .leading)
                    
                    Rectangle()
                        .fill(Color(NSColor.separatorColor).opacity(0.4))
                        .frame(width: 1)
                    
                    Text("작업자")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Rectangle()
                        .fill(Color(NSColor.separatorColor).opacity(0.4))
                        .frame(width: 1)
                    
                    // Attachment Column Header
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .center)
                        .help("첨부파일")
                    
                    Rectangle()
                        .fill(Color(NSColor.separatorColor).opacity(0.4))
                        .frame(width: 1)
                    
                    Text("완료")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .center)
                }
                .frame(height: store.headerHeight)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
            
            // Task List
            GeometryReader { geo in
                let viewportHeight = geo.size.height
                let totalContentHeight = CGFloat(store.flattenedRows.count + 1) * store.rowHeight
                let maxOffsetY = max(0, totalContentHeight - viewportHeight)
                
                ZStack(alignment: .topLeading) {
                    // 세로 오프셋은 ScrollOffsetView 만 실시간으로 읽고, 행 목록은 세로 구간이 바뀔 때만 다시 계산된다.
                    ScrollOffsetView(scroll: store.scroll, horizontal: false, vertical: .gantt) {
                        TreeRowsLayer(
                            store: store,
                            viewportHeight: viewportHeight,
                            totalContentHeight: totalContentHeight
                        )
                    }
                    
                    // Scroll wheel capture overlay for Tree
                    PanAndScrollOverlay(
                        onScroll: { _, dy in
                            store.scrollOffsetY = min(maxOffsetY, max(0, store.scrollOffsetY - dy))
                        },
                        onRightPan: { _, _ in }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .onDrop(of: [.text], delegate: TaskBackgroundDropDelegate(store: store))
            }
        }
        
        // Full-Height Draggable Splitter between "작업 트리" and "작업자"
        TreeColumnSplitter(store: store)
            .offset(x: store.treeNameWidth - 8)
    }
        .contentShape(Rectangle())
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TreeRowsLayer: View {
    @ObservedObject var store: ProjectStore
    let viewportHeight: CGFloat
    let totalContentHeight: CGFloat
    
    var body: some View {
        let rows = store.flattenedRows
        let rowHeight = store.rowHeight
        var window = store.scroll.rowWindow(viewportHeight: viewportHeight, rowHeight: rowHeight, totalRows: rows.count)
        // 인라인 편집 중인 행은 화면 밖이어도 항상 렌더링 (편집 필드가 사라지며 편집이 끝나는 것 방지)
        if let editingId = store.editingTaskId,
           let editingIndex = rows.firstIndex(where: { $0.id == editingId }) {
            window = min(window.lowerBound, editingIndex)..<max(window.upperBound, editingIndex + 1)
        }
        
        let topOffset = CGFloat(window.lowerBound) * rowHeight
        
        return VStack(spacing: 0) {
            ForEach(rows[window]) { row in
                TreeRowView(
                    store: store,
                    row: row
                )
                .frame(height: rowHeight)
                .background(
                    store.selectedTaskId == row.id ?
                        Color.accentColor.opacity(0.12) :
                        Color.clear
                )
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(NSColor.separatorColor).opacity(0.35)),
                    alignment: .bottom
                )
            }
            
            if window.upperBound >= rows.count {
                // Add Task row at bottom
                Button(action: {
                    _ = store.createNewTask(after: store.flattenedRows.last?.id)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("새 작업 추가...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onDrop(of: [.text], delegate: TaskBackgroundDropDelegate(store: store))
            }
            
            // Bottom empty space to click and clear filter/selection
            Color.clear
                .frame(height: max(100, viewportHeight))
                .contentShape(Rectangle())
                .onTapGesture {
                    if store.editingTaskId != nil {
                        store.commitInlineEditing()
                    }
                    store.selectedTaskId = nil
                    store.clearWorkloadFilter()
                }
        }
        .offset(y: topOffset)
    }
}

struct TreeRowView: View {
    @ObservedObject var store: ProjectStore
    let row: FlattenedTaskRow
    
    var task: TaskItem { row.task }
    
    var body: some View {
        HStack(spacing: 0) {
            // Task Name Column with folding indentation & drag grip
            HStack(spacing: 4) {
                // Indentation
                Spacer()
                    .frame(width: CGFloat(row.level) * 16)
                
                // Drag Grip Handle ("작업을 드래그해서 다른 곳으로 이동할 수 있도록 해")
                HStack(spacing: 0) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.45))
                }
                .frame(width: 14, height: 20)
                .contentShape(Rectangle())
                .cursor(.openHand)
                .onDrag {
                    store.draggedTaskId = task.id
                    // Safety auto-reset timeout in case the drag ends without a drop event
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        if NSEvent.pressedMouseButtons == 0 {
                            store.cleanupDragState()
                        }
                    }
                    return NSItemProvider(object: task.id.uuidString as NSString)
                }
                .help("드래그하여 작업 위치 또는 레벨 이동")
                
                // Fold / Unfold Arrow
                if row.hasChildren {
                    Button(action: {
                        store.toggleExpand(id: task.id)
                    }) {
                        Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .cursor(.pointingHand)
                    .help(row.isExpanded ? "하위 작업 접기" : "하위 작업 펼치기")
                } else {
                    Spacer().frame(width: 20)
                }
                
                // Color Dot
                if task.isMilestone {
                    Diamond()
                        .fill(Color(hex: task.colorHex))
                        .frame(width: 9, height: 9)
                } else {
                    Circle()
                        .fill(Color(hex: task.colorHex))
                        .frame(width: 8, height: 8)
                }
                
                // Task Detail Setting Trigger Badge
                Button(action: {
                    store.showDetail(for: task.id)
                }) {
                    Image(systemName: row.hasChildren ? "folder.fill" : (task.isMilestone ? "rhombus.fill" : "slider.horizontal.3"))
                        .font(.system(size: row.hasChildren ? 10 : (task.isMilestone ? 10 : 9), weight: .bold))
                        .foregroundColor(
                            row.hasChildren ?
                                (store.selectedTaskId == task.id ? Color.accentColor : Color(hex: task.colorHex)) :
                                (store.selectedTaskId == task.id ? Color.accentColor : Color.secondary.opacity(0.85))
                        )
                        .frame(width: 16, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help(row.hasChildren ? "상위 작업 세부 설정 열기 (하위 작업 보유)" : (task.isMilestone ? "마일스톤 세부 설정 열기" : "클릭 또는 더블클릭하여 작업 세부 설정 열기"))
                
                // Task Name (Inline edit or text display)
                if store.editingTaskId == task.id {
                    TreeInlineTextField(
                        initialText: store.editingTitle.isEmpty ? task.title : store.editingTitle,
                        onCommit: { newTitle in
                            store.commitInlineEditing(newTitle: newTitle)
                        },
                        onShiftEnter: { newTitle in
                            store.commitAndCreateNextTask(currentId: task.id, newTitle: newTitle)
                        },
                        onCancel: {
                            store.cancelInlineEditing()
                        },
                        onTextChanged: { currentText in
                            store.editingTitle = currentText
                        }
                    )
                    .id(task.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let hasNotes = !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    HStack(spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(
                                task.isCompleted ? Color.gray : Color(hex: task.colorHex)
                            )
                            .underline(hasNotes, color: task.isCompleted ? Color.gray.opacity(0.6) : Color(hex: task.colorHex).opacity(0.85))
                            .strikethrough(task.isCompleted, color: Color.gray.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(hasNotes ? "상세설명:\n\(task.notes)" : "")
                        
                        if store.selectedTaskId == task.id {
                            Button(action: {
                                store.startEditing(taskId: task.id)
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("작업 이름 수정")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .instantClick(
                        onSingleClick: {
                            store.cleanupDragState()
                            if store.selectedTaskId == task.id {
                                store.startEditing(taskId: task.id)
                            } else {
                                store.selectedTaskId = task.id
                                store.clearWorkloadFilter()
                            }
                        },
                        onDoubleClick: {
                            store.cleanupDragState()
                            store.showDetail(for: task.id)
                            store.clearWorkloadFilter()
                        }
                    )
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(width: store.treeNameWidth, alignment: .leading)
            
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.35))
                .frame(width: 1)
            
            // Assignees Column
            let hasChildren = !task.children.isEmpty
            let effectiveAssigneeIds = store.effectiveAssigneeIds(for: task)
            let assignedList = store.project.assignees.filter { effectiveAssigneeIds.contains($0.id) }
            
            HStack(spacing: 4) {
                if hasChildren {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                if assignedList.isEmpty {
                    Text(hasChildren ? "하위 작업자 없음" : "더블클릭하여 배정")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(assignedList) { a in
                                HStack(spacing: 3) {
                                    if let img = a.avatarImage {
                                        Image(nsImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 18, height: 18)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                            .foregroundColor(.blue.opacity(0.8))
                                    }
                                    Text(a.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color(NSColor.separatorColor).opacity(0.2))
                                .cornerRadius(4)
                            }
                            
                            if hasChildren {
                                Text("(합산)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .instantClick(
                onSingleClick: {
                    store.selectedTaskId = task.id
                    store.clearWorkloadFilter()
                },
                onDoubleClick: {
                    store.clearWorkloadFilter()
                    if hasChildren {
                        let alert = NSAlert()
                        alert.messageText = "작업자 직접 선택 불가"
                        alert.informativeText = "하위 작업이 있는 작업은 작업자를 직접 선택할 수 없습니다.\n하위 작업에 참여 중인 작업자들이 자동으로 합산되어 표시됩니다."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "확인")
                        alert.runModal()
                    } else {
                        store.assigneeManagerTaskId = task.id
                    }
                }
            )
            
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.35))
                .frame(width: 1)
            
            // Dedicated Attachment Column Cell
            Group {
                if !task.attachments.isEmpty {
                    Button(action: {
                        store.showDetail(for: task.id)
                    }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("첨부파일 \(task.attachments.count)개 (클릭하여 세부 설정 열기)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 34, height: store.rowHeight, alignment: .center)
            
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.35))
                .frame(width: 1)
            
            // Completed Status Checkbox
            Button(action: {
                store.toggleTaskCompletion(id: task.id)
                store.clearWorkloadFilter()
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(task.isCompleted ? .green : .secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: store.rowHeight, alignment: .center)
        }
        .contentShape(Rectangle())
        .opacity(
            // Only dim task row if it is genuinely being actively dragged by an active mouse press!
            (store.draggedTaskId == task.id && NSEvent.pressedMouseButtons != 0 && store.editingTaskId != task.id) ? 0.45 :
            (store.isTaskDimmedByWorkloadFilter(task: task) ? 0.38 : 1.0)
        )
        .animation(.easeInOut(duration: 0.2), value: store.isTaskDimmedByWorkloadFilter(task: task))
        .overlay(
            // Visual Drop Indicator ("위치에 따라 레벨을 잘 판단해서 이동")
            Group {
                if store.dropTargetId == task.id && store.draggedTaskId != task.id {
                    switch store.dropLocation {
                    case .above:
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .offset(x: CGFloat(row.level) * 16 + 12)
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2.5)
                            }
                            Spacer()
                        }
                    case .below:
                        VStack(spacing: 0) {
                            Spacer()
                            HStack(spacing: 0) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .offset(x: CGFloat(row.level) * 16 + 12)
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2.5)
                            }
                        }
                    case .inside:
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 2)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.12))
                            
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("하위 작업으로 이동")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(4)
                                .shadow(color: Color.black.opacity(0.15), radius: 2)
                                .padding(.trailing, 10)
                            }
                        }
                    case .none:
                        EmptyView()
                    }
                }
            }
        )
        .onDrop(of: [.text], delegate: TaskRowDropDelegate(targetRow: row, store: store))
        .contextMenu {
            Button(task.isMilestone ? "마일스톤 세부 정보..." : "세부 정보...") {
                store.showDetail(for: task.id)
            }
            Button("작업 이름 변경") {
                store.startEditing(taskId: task.id)
            }
            
            if task.children.isEmpty {
                Button("작업자 배정...") {
                    store.assigneeManagerTaskId = task.id
                }
            } else {
                Button("작업자 배정 (하위 작업 자동 합산됨)") {
                }
                .disabled(true)
            }
            
            Divider()
            
            Button("위로 이동 (⌘↑)") {
                store.selectedTaskId = task.id
                store.moveSelectedTaskUpInTree()
            }
            Button("아래로 이동 (⌘↓)") {
                store.selectedTaskId = task.id
                store.moveSelectedTaskDownInTree()
            }
            
            Divider()
            
            Button("하위 레벨로 들여쓰기 (⌘→)") {
                store.indentTask(id: task.id)
            }
            Button("상위 레벨로 내어쓰기 (⌘←)") {
                store.outdentTask(id: task.id)
            }
            
            Divider()
            
            Button("다음 위치에 작업 추가") {
                _ = store.createNewTask(after: task.id, asChild: false)
            }
            Button("하위 작업 추가") {
                _ = store.createNewTask(after: task.id, asChild: true)
            }
            Divider()
            Button(role: .destructive, action: {
                store.deleteTask(id: task.id)
            }) {
                Text("작업 삭제")
            }
        }
    }
}

// MARK: - Tree Drag & Drop Delegates
struct TaskRowDropDelegate: DropDelegate {
    let targetRow: FlattenedTaskRow
    let store: ProjectStore
    
    func validateDrop(info: DropInfo) -> Bool {
        guard let sourceId = store.draggedTaskId else {
            return info.hasItemsConforming(to: [.text])
        }
        if sourceId == targetRow.id { return false }
        if store.isTaskDescendant(parentId: sourceId, candidateId: targetRow.id) { return false }
        return true
    }
    
    func dropEntered(info: DropInfo) {
        updateDrop(info: info)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else {
            return DropProposal(operation: .forbidden)
        }
        updateDrop(info: info)
        return DropProposal(operation: .move)
    }
    
    private func updateDrop(info: DropInfo) {
        let y = info.location.y
        let h = store.rowHeight
        
        // Upper 28%: above (same level sibling before)
        // Lower 28%: below (same level sibling after)
        // Middle 44%: inside (child of target task)
        if y < h * 0.28 {
            store.dropLocation = .above
        } else if y > h * 0.72 {
            store.dropLocation = .below
        } else {
            store.dropLocation = .inside
        }
        store.dropTargetId = targetRow.id
    }
    
    func dropExited(info: DropInfo) {
        if store.dropTargetId == targetRow.id {
            store.dropTargetId = nil
            store.dropLocation = nil
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let location = store.dropLocation ?? .inside
        
        if let sourceId = store.draggedTaskId {
            guard validateDrop(info: info) else {
                cleanup()
                return false
            }
            let success = store.moveTask(sourceId: sourceId, targetId: targetRow.id, location: location)
            cleanup()
            return success
        }
        
        if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                if let str = item as? String, let uuid = UUID(uuidString: str) {
                    DispatchQueue.main.async {
                        _ = store.moveTask(sourceId: uuid, targetId: targetRow.id, location: location)
                        cleanup()
                    }
                }
            }
            return true
        }
        
        cleanup()
        return false
    }
    
    private func cleanup() {
        store.cleanupDragState()
    }
}

struct TaskBackgroundDropDelegate: DropDelegate {
    let store: ProjectStore
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard store.draggedTaskId != nil || info.hasItemsConforming(to: [.text]) else {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        if let sourceId = store.draggedTaskId {
            let success = store.moveTaskToEndOfRoot(sourceId: sourceId)
            store.cleanupDragState()
            return success
        }
        
        if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                if let str = item as? String, let uuid = UUID(uuidString: str) {
                    DispatchQueue.main.async {
                        _ = store.moveTaskToEndOfRoot(sourceId: uuid)
                        store.cleanupDragState()
                    }
                }
            }
            return true
        }
        return false
    }
}

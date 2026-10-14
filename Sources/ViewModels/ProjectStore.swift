import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum TaskDropLocation: String, Codable {
    case above
    case inside
    case below
}

struct WorkloadFilterState: Equatable {
    var assigneeId: UUID
    var date: Date
}

@MainActor
class ProjectStore: ObservableObject {
    private var isSuppressedDirty: Bool = false
    
    @Published var project: ProjectData {
        didSet {
            if !isSuppressedDirty {
                isDirty = true
            }
            invalidateCache()
        }
    }
    
    @Published var currentFileURL: URL? = nil {
        didSet {
            updateMainWindowRepresentation()
        }
    }
    @Published var isDirty: Bool = false {
        didSet {
            updateMainWindowRepresentation()
        }
    }
    
    // MARK: - Undo History (Max 10 steps)
    private var undoStack: [ProjectData] = []
    private let maxUndoSteps = 10
    
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    func recordUndo() {
        undoStack.append(project)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
    }
    
    func undo() {
        guard let previousProject = undoStack.popLast() else { return }
        self.project = previousProject
        syncHierarchy()
        invalidateCache()
        
        if let sel = selectedTaskId, findTask(id: sel) == nil {
            selectedTaskId = project.tasks.first?.id
        }
        if let det = detailTask {
            detailTask = findTask(id: det.id)
        }
    }
    
    func clearUndoHistory() {
        undoStack.removeAll()
    }
    
    // Window Title with loaded file name
    var windowTitle: String {
        let displayName: String
        if let fileURL = currentFileURL {
            displayName = fileURL.lastPathComponent
        } else {
            displayName = project.title.isEmpty ? "새 프로젝트" : project.title
        }
        return "Gantt Lab - \(displayName)\(isDirty ? " *" : "")"
    }
    
    func updateMainWindowRepresentation() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for window in NSApp.windows {
                if window.canBecomeMain {
                    window.title = self.windowTitle
                    window.representedURL = self.currentFileURL
                    window.isDocumentEdited = self.isDirty
                }
            }
        }
    }
    
    // Selection and Modal Sheets
    @Published var selectedTaskId: UUID? = nil {
        didSet {
            cleanupDragState()
            if oldValue != selectedTaskId && editingTaskId != nil && editingTaskId != selectedTaskId {
                commitInlineEditing()
            }
        }
    }
    @Published var editingTaskId: UUID? = nil
    var editingTitle: String = ""
    @Published var detailTask: TaskItem? = nil
    @Published var assigneeManagerTaskId: UUID? = nil
    @Published var showAboutView: Bool = false
    @Published var showExportAssigneeTasksSheet: Bool = false
    @Published var showExportAllAssigneesSheet: Bool = false
    @Published var showUnsavedAlert: Bool = false
    @Published var pendingNewProjectAction: (() -> Void)? = nil
    @Published var attachmentReport: AttachmentIntegrityReport? = nil
    
    // Inline task name editing helpers
    func startEditing(taskId: UUID) {
        cleanupDragState()
        if editingTaskId != nil && editingTaskId != taskId {
            commitInlineEditing()
        }
        if let task = findTask(id: taskId) {
            selectedTaskId = taskId
            editingTaskId = taskId
            editingTitle = task.title
        }
    }
    
    func commitInlineEditing(newTitle: String? = nil) {
        cleanupDragState()
        guard let editingId = editingTaskId else { return }
        let titleToCommit = newTitle ?? editingTitle
        let trimmed = titleToCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        if var t = findTask(id: editingId) {
            if !trimmed.isEmpty && trimmed != t.title {
                recordUndo()
                t.title = trimmed
                updateTask(t)
            }
        }
        editingTaskId = nil
        editingTitle = ""
    }
    
    func cancelInlineEditing() {
        cleanupDragState()
        editingTaskId = nil
        editingTitle = ""
    }
    
    // Drag & Drop Tree Reordering State
    @Published var draggedTaskId: UUID? = nil
    @Published var dropTargetId: UUID? = nil
    @Published var dropLocation: TaskDropLocation? = nil
    
    func cleanupDragState() {
        if draggedTaskId != nil || dropTargetId != nil || dropLocation != nil {
            draggedTaskId = nil
            dropTargetId = nil
            dropLocation = nil
        }
    }
    
    // Workload Inspection Filter State
    @Published var selectedWorkloadFilter: WorkloadFilterState? = nil
    private var autoSaveTimer: Timer? = nil
    
    // Coordinated Scrolling & Layout Split
    // 스크롤 오프셋은 성능을 위해 ProjectStore(@Published)에서 분리된 ScrollModel(@Observable)에 저장한다.
    // (기존처럼 @Published 로 두면 1픽셀 스크롤마다 앱 전체 View가 다시 계산됨)
    // 아래 computed 속성은 기존 코드/바인딩($store.scrollOffsetX) 호환을 위한 전달자(forwarder)다.
    let scroll = ScrollModel()
    var scrollOffsetX: CGFloat {
        get { scroll.x }
        set { scroll.setX(newValue) }
    }
    var scrollOffsetY: CGFloat {
        get { scroll.y }
        set { scroll.setY(newValue) }
    }
    var workloadScrollOffsetY: CGFloat {
        get { scroll.workloadY }
        set { scroll.setWorkloadY(newValue) }
    }
    @Published var leftPaneWidth: CGFloat = 380 {
        didSet {
            let maxTree = max(110, leftPaneWidth - 180)
            if treeNameWidth > maxTree {
                treeNameWidth = maxTree
            }
            saveLayoutSettings()
        }
    }
    @Published var treeNameWidth: CGFloat = 220 {
        didSet {
            saveLayoutSettings()
        }
    }
    @Published var bottomPaneHeight: CGFloat = 170 {
        didSet {
            saveLayoutSettings()
        }
    }
    
    // Timeline viewport settings
    @Published var timelineStartDate: Date = Date().startOfDay.addingDays(-5)
    @Published var timelineTotalDays: Int = 45
    @Published var dayWidth: CGFloat = 36.0 {
        didSet {
            scroll.configure(dayWidth: dayWidth, rowHeight: rowHeight)
        }
    }
    let rowHeight: CGFloat = 38.0
    let headerHeight: CGFloat = 50.0
    
    static var ganttLabType: UTType {
        UTType(filenameExtension: "ganttlab") ?? .data
    }
    
    func showDetail(for taskId: UUID) {
        if editingTaskId != nil {
            commitInlineEditing()
        }
        if let task = findTask(id: taskId) {
            self.detailTask = task
            TaskDetailWindowManager.shared.show(taskId: taskId, store: self)
        }
    }
    
    func clampScroll(maxOffsetX: CGFloat, maxOffsetY: CGFloat) {
        if scrollOffsetX > maxOffsetX { scrollOffsetX = max(0, maxOffsetX) }
        if scrollOffsetX < 0 { scrollOffsetX = 0 }
        if scrollOffsetY > maxOffsetY { scrollOffsetY = max(0, maxOffsetY) }
        if scrollOffsetY < 0 { scrollOffsetY = 0 }
    }
    
    // MARK: - High-Performance Coordinated Scrolling
    /// Smooth atomic 2D pan scroll for Gantt Chart (Right-click drag & Wheel)
    /// Applies an optimized speed multiplier and updates both axes cleanly.
    func panScroll(deltaX: CGFloat, deltaY: CGFloat, maxOffsetX: CGFloat, maxOffsetY: CGFloat, speedMultiplier: CGFloat = 1.25) {
        let appliedDx = deltaX * speedMultiplier
        let appliedDy = deltaY * speedMultiplier
        
        let newX = min(maxOffsetX, max(0, scrollOffsetX - appliedDx))
        let newY = min(maxOffsetY, max(0, scrollOffsetY + appliedDy))
        
        if newX != scrollOffsetX || newY != scrollOffsetY {
            scrollOffsetX = newX
            scrollOffsetY = newY
        }
    }
    
    /// Standard scroll delta update for trackpad / wheel
    func scrollBy(deltaX: CGFloat, deltaY: CGFloat, maxOffsetX: CGFloat, maxOffsetY: CGFloat) {
        let newX = min(maxOffsetX, max(0, scrollOffsetX - deltaX))
        let newY = min(maxOffsetY, max(0, scrollOffsetY - deltaY))
        
        if newX != scrollOffsetX || newY != scrollOffsetY {
            scrollOffsetX = newX
            scrollOffsetY = newY
        }
    }
    
    /// Workload panel synchronized horizontal and vertical pan scroll
    func panScrollWorkload(deltaX: CGFloat, deltaY: CGFloat, maxOffsetX: CGFloat, maxOffsetY: CGFloat, speedMultiplier: CGFloat = 1.25) {
        let appliedDx = deltaX * speedMultiplier
        let appliedDy = deltaY * speedMultiplier
        
        let newX = min(maxOffsetX, max(0, scrollOffsetX - appliedDx))
        let newY = min(maxOffsetY, max(0, workloadScrollOffsetY + appliedDy))
        
        if newX != scrollOffsetX || newY != workloadScrollOffsetY {
            scrollOffsetX = newX
            workloadScrollOffsetY = newY
        }
    }
    
    // MARK: - Persistent Layout Preferences (Stored in Mac Cache/UserDefaults, not in ganttlab file)
    private static let keyLeftPaneWidth = "GanttLab_LeftPaneWidth"
    private static let keyTreeNameWidth = "GanttLab_TreeNameWidth"
    private static let keyBottomPaneHeight = "GanttLab_BottomPaneHeight"
    
    func saveLayoutSettings() {
        let defaults = UserDefaults.standard
        defaults.set(Double(leftPaneWidth), forKey: Self.keyLeftPaneWidth)
        defaults.set(Double(treeNameWidth), forKey: Self.keyTreeNameWidth)
        defaults.set(Double(bottomPaneHeight), forKey: Self.keyBottomPaneHeight)
    }
    
    func loadLayoutSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.keyLeftPaneWidth) != nil {
            let savedLeft = defaults.double(forKey: Self.keyLeftPaneWidth)
            if savedLeft >= 200 && savedLeft <= 1200 {
                self.leftPaneWidth = CGFloat(savedLeft)
            }
        }
        if defaults.object(forKey: Self.keyTreeNameWidth) != nil {
            let savedTree = defaults.double(forKey: Self.keyTreeNameWidth)
            if savedTree >= 100 && savedTree <= 900 {
                self.treeNameWidth = CGFloat(savedTree)
            }
        }
        if defaults.object(forKey: Self.keyBottomPaneHeight) != nil {
            let savedBottom = defaults.double(forKey: Self.keyBottomPaneHeight)
            if savedBottom >= 60 && savedBottom <= 600 {
                self.bottomPaneHeight = CGFloat(savedBottom)
            }
        }
    }
    
    // MARK: - Today Alignment
    /// Align timeline scroll position so Today is placed at offsetDaysFromLeft from the left edge of Gantt chart viewport.
    /// (offsetDaysFromLeft = 2 places Today at +2 days from the left, meaning the left edge is Today - 2 days)
    func scrollToToday(offsetDaysFromLeft: Int = 2) {
        let today = Date().startOfDay
        let daysToToday = timelineStartDate.daysBetween(today)
        let todayPixelX = CGFloat(daysToToday) * dayWidth
        let targetX = todayPixelX - (CGFloat(offsetDaysFromLeft) * dayWidth)
        self.scrollOffsetX = max(0, targetX)
    }
    
    // MARK: - Performance Caches
    // In-memory cache for flattened rows, flat tasks list, and workload counts to make clicks/drags instant (0ms latency)
    private var _cachedFlatRows: [FlattenedTaskRow]? = nil
    private var _cachedFlatTasks: [TaskItem]? = nil
    private var _cachedWorkloadMap: [UUID: [Int: Int]]? = nil
    // 워크로드 맵의 Int 키(날짜 인덱스)가 기준으로 삼은 타임라인 시작일/길이
    private var _workloadMapBaseStart: Date? = nil
    private var _workloadMapBaseTotal: Int = 0
    
    // 날짜 메타데이터 캐시 (헤더/그리드/워크로드 공용)
    private var _dayInfoCache: [TimelineDay] = []
    private var _dayInfoCacheStart: Date? = nil
    private var _dayInfoCacheToday: Date? = nil
    
    init() {
        isSuppressedDirty = true
        defer {
            isSuppressedDirty = false
            self.isDirty = false
            clearUndoHistory()
            updateMainWindowRepresentation()
        }
        
        let initialData = ProjectData.createSampleProject()
        self.project = initialData
        self.project.assignees.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        // Restore layout preferences from Mac Cache / UserDefaults
        loadLayoutSettings()
        
        // Auto-load last saved project if available
        if let lastPath = UserDefaults.standard.string(forKey: "LastSavedProjectFilePath"),
           FileManager.default.fileExists(atPath: lastPath) {
            let fileURL = URL(fileURLWithPath: lastPath)
            loadProject(from: fileURL, isAutoLoad: true)
        } else {
            syncHierarchy()
            invalidateCache()
            // Milestone window presentation is safely handled in MainView.onAppear
            // after the main window has been fully initialized and presented.
        }
        
        // Configure virtualization bucket sizes for the scroll model
        scroll.configure(dayWidth: dayWidth, rowHeight: rowHeight)
        
        // Position Today at 2 days from the left edge (left edge is Today - 2 days)
        scrollToToday(offsetDaysFromLeft: 2)
        
        // Start 10-minute auto save timer
        startAutoSaveTimer()
    }
    
    func invalidateCache() {
        _cachedFlatRows = nil
        _cachedFlatTasks = nil
        _cachedWorkloadMap = nil
        recalculateTimelineRange()
    }
    
    // MARK: - Timeline Range Calculation
    func recalculateTimelineRange() {
        let allTasks = getAllTasksFlat()
        let today = Date().startOfDay
        guard !allTasks.isEmpty else {
            setTimelineRange(start: today.addingDays(-5), totalDays: 75)
            return
        }
        
        let minStart = allTasks.map { $0.effectiveStartDate }.min() ?? today
        let maxEnd = allTasks.map { $0.effectiveEndDate }.max() ?? today.addingDays(14)
        
        // Ensure timeline begins with buffer before both earliest task and today-2
        let earliestDate = min(minStart, today.addingDays(-5))
        let paddedStart = earliestDate.addingDays(-5)
        let daysByTasks = paddedStart.daysBetween(maxEnd) + 30
        
        setTimelineRange(start: paddedStart, totalDays: max(75, daysByTasks))
    }
    
    /// 값이 실제로 바뀔 때만 @Published 에 대입 (불필요한 전체 화면 갱신 방지)
    private func setTimelineRange(start: Date, totalDays: Int) {
        if timelineStartDate != start {
            timelineStartDate = start
        }
        if timelineTotalDays != totalDays {
            timelineTotalDays = totalDays
        }
    }
    
    // MARK: - Precomputed Timeline Day Info
    /// 요청한 범위의 날짜 메타데이터를 반환한다. (DateFormatter/Calendar 연산은 날짜당 한 번만 수행)
    /// 타임라인 시작일이나 "오늘"이 바뀌면 캐시를 자동으로 다시 만든다.
    func timelineDays(_ range: Range<Int>) -> ArraySlice<TimelineDay> {
        guard !range.isEmpty, range.lowerBound >= 0 else { return [] }
        let today = Date().startOfDay
        if _dayInfoCacheStart != timelineStartDate || _dayInfoCacheToday != today {
            _dayInfoCache.removeAll(keepingCapacity: true)
            _dayInfoCacheStart = timelineStartDate
            _dayInfoCacheToday = today
        }
        if _dayInfoCache.count < range.upperBound {
            let calendar = Calendar.current
            for index in _dayInfoCache.count..<range.upperBound {
                let date = timelineStartDate.addingDays(index)
                let weekday = calendar.component(.weekday, from: date)
                _dayInfoCache.append(TimelineDay(
                    index: index,
                    date: date,
                    dayNumber: calendar.component(.day, from: date),
                    isWeekend: weekday == 1 || weekday == 7,
                    isToday: date == today,
                    monthLabel: String(date.formattedDateString.prefix(7)),
                    shortLabel: date.shortDateString,
                    weekdayLabel: date.dayOfWeekString
                ))
            }
        }
        return _dayInfoCache[range]
    }
    
    /// 워크로드 필터 날짜의 타임라인 인덱스 (필터가 없으면 nil)
    var workloadFilterDayIndex: Int? {
        guard let filter = selectedWorkloadFilter else { return nil }
        return timelineStartDate.daysBetween(filter.date)
    }
    
    func ensureTimelineCovers(visibleWidth: CGFloat) {
        let daysNeeded = Int(ceil(visibleWidth / dayWidth)) + 15
        if daysNeeded > timelineTotalDays {
            timelineTotalDays = daysNeeded
        }
    }
    
    // MARK: - Flattened Rows for Tree & Gantt Synchronization
    var flattenedRows: [FlattenedTaskRow] {
        if let cached = _cachedFlatRows {
            return cached
        }
        var rows: [FlattenedTaskRow] = []
        func traverse(items: [TaskItem], level: Int, parentId: UUID?) {
            for item in items {
                rows.append(FlattenedTaskRow(task: item, level: level, parentId: parentId))
                if item.isExpanded && !item.children.isEmpty {
                    traverse(items: item.children, level: level + 1, parentId: item.id)
                }
            }
        }
        traverse(items: project.tasks, level: 0, parentId: nil)
        _cachedFlatRows = rows
        return rows
    }
    
    func getAllTasksFlat() -> [TaskItem] {
        if let cached = _cachedFlatTasks {
            return cached
        }
        var result: [TaskItem] = []
        func traverse(items: [TaskItem]) {
            for item in items {
                result.append(item)
                traverse(items: item.children)
            }
        }
        traverse(items: project.tasks)
        _cachedFlatTasks = result
        return result
    }
    
    func findTask(id: UUID) -> TaskItem? {
        // Fast search using flat tasks
        return getAllTasksFlat().first(where: { $0.id == id })
    }
    
    /// Returns all ancestor tasks in root-to-parent order for a given task ID
    func getAncestorTasks(for taskId: UUID) -> [TaskItem] {
        var ancestors: [TaskItem] = []
        
        func findPath(in items: [TaskItem], currentPath: [TaskItem]) -> Bool {
            for item in items {
                if item.id == taskId {
                    ancestors = currentPath
                    return true
                }
                if !item.children.isEmpty {
                    if findPath(in: item.children, currentPath: currentPath + [item]) {
                        return true
                    }
                }
            }
            return false
        }
        
        _ = findPath(in: project.tasks, currentPath: [])
        return ancestors
    }
    
    // Update a task in-place in tree
    func updateTask(_ updated: TaskItem) {
        func update(items: inout [TaskItem]) -> Bool {
            for i in 0..<items.count {
                if items[i].id == updated.id {
                    items[i] = updated
                    return true
                }
                if update(items: &items[i].children) {
                    return true
                }
            }
            return false
        }
        _ = update(items: &project.tasks)
        syncHierarchy()
        invalidateCache()
    }
    
    // Helper to collect all IDs in a task's subtree
    func collectSubtreeIds(from id: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [id]
        if let task = findTask(id: id) {
            func collect(item: TaskItem) {
                ids.insert(item.id)
                for child in item.children {
                    collect(item: child)
                }
            }
            collect(item: task)
        }
        return ids
    }
    
    // Delete task, all its children/descendants, and all associated dependencies
    func deleteTask(id: UUID) {
        recordUndo()
        
        let allDeletedIds = collectSubtreeIds(from: id)
        
        func remove(items: inout [TaskItem]) -> Bool {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items.remove(at: index)
                return true
            }
            for i in 0..<items.count {
                if remove(items: &items[i].children) {
                    return true
                }
            }
            return false
        }
        _ = remove(items: &project.tasks)
        project.dependencies.removeAll { allDeletedIds.contains($0.fromTaskId) || allDeletedIds.contains($0.toTaskId) }
        
        if let sel = selectedTaskId, allDeletedIds.contains(sel) {
            selectedTaskId = nil
        }
        if let det = detailTask, allDeletedIds.contains(det.id) {
            detailTask = nil
        }
        
        syncHierarchy()
        invalidateCache()
    }
    
    /// Delete currently selected task (and all its children) when Del key or Delete button is pressed
    func deleteSelectedTask() {
        guard let selectedId = selectedTaskId else { return }
        
        let flat = flattenedRows
        var nextSelectionId: UUID? = nil
        if let currentIndex = flat.firstIndex(where: { $0.id == selectedId }) {
            let descendantIds = collectSubtreeIds(from: selectedId)
            // Pick next non-deleted task in flat rows; fallback to previous non-deleted task
            if let nextRow = flat[(currentIndex + 1)...].first(where: { !descendantIds.contains($0.id) }) {
                nextSelectionId = nextRow.id
            } else if let prevRow = flat[..<currentIndex].last(where: { !descendantIds.contains($0.id) }) {
                nextSelectionId = prevRow.id
            }
        }
        
        deleteTask(id: selectedId)
        selectedTaskId = nextSelectionId
    }
    
    // MARK: - Task Completion Toggle (Sync Children & Ancestors)
    /// "하위 작업이 있는 상위 작업을 선택하고 완료 버튼을 클릭하면 하위 작업도 모두 완료 상태로 변경. 반대로 완료를 취소하면 하위 작업도 모두 완료 해제."
    func toggleTaskCompletion(id: UUID) {
        guard let task = findTask(id: id) else { return }
        recordUndo()
        
        let targetCompletion = !task.isCompleted
        
        func applyCompletionRecursive(_ node: inout TaskItem, state: Bool) {
            node.isCompleted = state
            for i in 0..<node.children.count {
                applyCompletionRecursive(&node.children[i], state: state)
            }
        }
        
        func setCompletion(items: inout [TaskItem], targetId: UUID, state: Bool) -> Bool {
            for i in 0..<items.count {
                if items[i].id == targetId {
                    applyCompletionRecursive(&items[i], state: state)
                    return true
                }
                if setCompletion(items: &items[i].children, targetId: targetId, state: state) {
                    return true
                }
            }
            return false
        }
        
        _ = setCompletion(items: &project.tasks, targetId: id, state: targetCompletion)
        syncHierarchy()
        invalidateCache()
        
        if detailTask?.id == id {
            detailTask = findTask(id: id)
        }
    }
    
    // Ultra-Fast Lightweight Tree Fold/Unfold (0ms instant response)
    // Avoids wiping workload cache and recalculating timeline dates since dates/assignees never change on fold!
    func toggleExpand(id: UUID) {
        func toggle(items: inout [TaskItem]) -> Bool {
            for i in 0..<items.count {
                if items[i].id == id {
                    items[i].isExpanded.toggle()
                    return true
                }
                if toggle(items: &items[i].children) {
                    return true
                }
            }
            return false
        }
        
        guard toggle(items: &project.tasks) else { return }
        _cachedFlatRows = nil
        objectWillChange.send()
    }
    
    // MARK: - Task Creation Logic
    @discardableResult
    func createNewTask(after precedingId: UUID? = nil, asChild: Bool = false) -> UUID {
        recordUndo()
        let today = Date().startOfDay
        let endDate = today.addingDays(7)
        
        var inheritColor = Palette.defaultColor
        let flat = flattenedRows
        if let precedingId = precedingId {
            if let idx = flat.firstIndex(where: { $0.id == precedingId }) {
                inheritColor = flat[idx].task.colorHex
            }
        } else if let last = flat.last {
            inheritColor = last.task.colorHex
        }
        
        let newTask = TaskItem(
            title: asChild ? "새 하위 작업" : "새 작업",
            startDate: today,
            endDate: endDate,
            isCompleted: false,
            colorHex: inheritColor,
            assigneeIds: [],
            notes: "",
            isExpanded: true,
            children: []
        )
        
        if let precedingId = precedingId {
            if asChild {
                if let parent = findTask(id: precedingId), parent.isMilestone {
                    let alert = NSAlert()
                    alert.messageText = "하위 작업 추가 불가"
                    alert.informativeText = "마일스톤은 하위 작업을 가질 수 없습니다."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "확인")
                    alert.runModal()
                    return precedingId
                }
                func addChild(to items: inout [TaskItem]) -> Bool {
                    for i in 0..<items.count {
                        if items[i].id == precedingId {
                            items[i].children.append(newTask)
                            items[i].isExpanded = true
                            return true
                        }
                        if addChild(to: &items[i].children) {
                            return true
                        }
                    }
                    return false
                }
                _ = addChild(to: &project.tasks)
            } else {
                func insertSibling(in items: inout [TaskItem]) -> Bool {
                    if let idx = items.firstIndex(where: { $0.id == precedingId }) {
                        items.insert(newTask, at: idx + 1)
                        return true
                    }
                    for i in 0..<items.count {
                        if insertSibling(in: &items[i].children) {
                            return true
                        }
                    }
                    return false
                }
                if !insertSibling(in: &project.tasks) {
                    project.tasks.append(newTask)
                }
            }
        } else {
            project.tasks.append(newTask)
        }
        
        invalidateCache()
        self.selectedTaskId = newTask.id
        self.editingTaskId = newTask.id
        self.editingTitle = newTask.title
        return newTask.id
    }
    
    // MARK: - Shift-Enter Handling
    func commitAndCreateNextTask(currentId: UUID, newTitle: String? = nil) {
        commitInlineEditing(newTitle: newTitle)
        _ = createNewTask(after: currentId, asChild: false)
    }
    
    // MARK: - Tree Level Indent & Outdent (Cmd + Left / Right Cursor Keys)
    /// Whether tasks can be indented/outdented/moved in the tree hierarchy
    var isTaskTreeManipulationAllowed: Bool {
        guard selectedTaskId != nil else { return false }
        if editingTaskId != nil { return false }
        if detailTask != nil { return false }
        if let keyWin = NSApp.keyWindow, keyWin == TaskDetailWindowManager.shared.window {
            return false
        }
        return true
    }
    
    /// Indent: Move task into the immediately preceding sibling's children
    func indentSelectedTask() {
        guard isTaskTreeManipulationAllowed, let selectedId = selectedTaskId else { return }
        indentTask(id: selectedId)
    }
    
    /// Outdent: Move task out to the parent's level
    func outdentSelectedTask() {
        guard isTaskTreeManipulationAllowed, let selectedId = selectedTaskId else { return }
        outdentTask(id: selectedId)
    }
    
    func indentTask(id: UUID) {
        recordUndo()
        func process(items: inout [TaskItem]) -> Bool {
            if let idx = items.firstIndex(where: { $0.id == id }) {
                guard idx > 0 else { return false } // First child cannot be indented
                if items[idx - 1].isMilestone {
                    let alert = NSAlert()
                    alert.messageText = "하위 작업 추가 불가"
                    alert.informativeText = "마일스톤은 하위 작업을 가질 수 없습니다."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "확인")
                    alert.runModal()
                    return false
                }
                let moving = items.remove(at: idx)
                items[idx - 1].children.append(moving)
                items[idx - 1].isExpanded = true
                return true
            }
            for i in 0..<items.count {
                if process(items: &items[i].children) {
                    return true
                }
            }
            return false
        }
        
        if process(items: &project.tasks) {
            syncHierarchy()
            invalidateCache()
        }
    }
    
    func outdentTask(id: UUID) {
        // If already top level, cannot outdent further
        if project.tasks.contains(where: { $0.id == id }) {
            return
        }
        recordUndo()
        
        // Check if direct child of a top-level item
        if let pIdx = project.tasks.firstIndex(where: { $0.children.contains(where: { $0.id == id }) }) {
            if let cIdx = project.tasks[pIdx].children.firstIndex(where: { $0.id == id }) {
                let moving = project.tasks[pIdx].children.remove(at: cIdx)
                project.tasks.insert(moving, at: pIdx + 1)
                syncHierarchy()
                invalidateCache()
                return
            }
        }
        
        // Recursive deeper outdent
        func processDeep(nodes: inout [TaskItem]) -> Bool {
            for pIdx in 0..<nodes.count {
                if let cIdx = nodes[pIdx].children.firstIndex(where: { child in
                    child.children.contains(where: { $0.id == id })
                }) {
                    if let targetIdx = nodes[pIdx].children[cIdx].children.firstIndex(where: { $0.id == id }) {
                        let moving = nodes[pIdx].children[cIdx].children.remove(at: targetIdx)
                        nodes[pIdx].children.insert(moving, at: cIdx + 1)
                        return true
                    }
                }
                if processDeep(nodes: &nodes[pIdx].children) {
                    return true
                }
            }
            return false
        }
        
        if processDeep(nodes: &project.tasks) {
            syncHierarchy()
            invalidateCache()
        }
    }
    
    // MARK: - Tree Drag & Drop Reordering (Move Tasks between levels and positions)
    func isTaskDescendant(parentId: UUID, candidateId: UUID) -> Bool {
        guard let parent = findTask(id: parentId) else { return false }
        func checkDescendant(task: TaskItem) -> Bool {
            if task.id == candidateId { return true }
            for child in task.children {
                if checkDescendant(task: child) {
                    return true
                }
            }
            return false
        }
        for child in parent.children {
            if checkDescendant(task: child) {
                return true
            }
        }
        return false
    }
    
    @discardableResult
    func moveTask(sourceId: UUID, targetId: UUID, location: TaskDropLocation) -> Bool {
        guard sourceId != targetId else { return false }
        if isTaskDescendant(parentId: sourceId, candidateId: targetId) {
            return false
        }
        recordUndo()
        
        // 1. Extract moving task from tree
        func extract(id: UUID, from items: inout [TaskItem]) -> TaskItem? {
            if let idx = items.firstIndex(where: { $0.id == id }) {
                return items.remove(at: idx)
            }
            for i in 0..<items.count {
                if let found = extract(id: id, from: &items[i].children) {
                    return found
                }
            }
            return nil
        }
        
        guard let movingTask = extract(id: sourceId, from: &project.tasks) else {
            return false
        }
        
        // 2. Insert into target position according to location
        var inserted = false
        
        switch location {
        case .inside:
            if let target = findTask(id: targetId), target.isMilestone {
                return false
            }
            // "레벨에 따라 다른 작업의 하위에 들어갈 수도 있으니 위치에 따라 레벨을 잘 판단해서 이동하도록 해."
            func insertChild(into items: inout [TaskItem]) -> Bool {
                for i in 0..<items.count {
                    if items[i].id == targetId {
                        items[i].children.append(movingTask)
                        items[i].isExpanded = true
                        return true
                    }
                    if insertChild(into: &items[i].children) {
                        return true
                    }
                }
                return false
            }
            inserted = insertChild(into: &project.tasks)
            
        case .above:
            // Insert as sibling before target
            func insertSiblingAbove(in items: inout [TaskItem]) -> Bool {
                if let idx = items.firstIndex(where: { $0.id == targetId }) {
                    items.insert(movingTask, at: idx)
                    return true
                }
                for i in 0..<items.count {
                    if insertSiblingAbove(in: &items[i].children) {
                        return true
                    }
                }
                return false
            }
            inserted = insertSiblingAbove(in: &project.tasks)
            
        case .below:
            // Insert as sibling after target
            func insertSiblingBelow(in items: inout [TaskItem]) -> Bool {
                if let idx = items.firstIndex(where: { $0.id == targetId }) {
                    items.insert(movingTask, at: idx + 1)
                    return true
                }
                for i in 0..<items.count {
                    if insertSiblingBelow(in: &items[i].children) {
                        return true
                    }
                }
                return false
            }
            inserted = insertSiblingBelow(in: &project.tasks)
        }
        
        if !inserted {
            // Fallback: append at root level so item is never lost
            project.tasks.append(movingTask)
        }
        
        syncHierarchy()
        invalidateCache()
        selectedTaskId = sourceId
        return true
    }
    
    @discardableResult
    func moveTaskToEndOfRoot(sourceId: UUID) -> Bool {
        recordUndo()
        func extract(id: UUID, from items: inout [TaskItem]) -> TaskItem? {
            if let idx = items.firstIndex(where: { $0.id == id }) {
                return items.remove(at: idx)
            }
            for i in 0..<items.count {
                if let found = extract(id: id, from: &items[i].children) {
                    return found
                }
            }
            return nil
        }
        
        guard let movingTask = extract(id: sourceId, from: &project.tasks) else {
            return false
        }
        project.tasks.append(movingTask)
        syncHierarchy()
        invalidateCache()
        selectedTaskId = sourceId
        return true
    }
    
    // MARK: - Effective Assignees (Parent with children aggregates all child assignees)
    /// "하위작업이 있는 작업의 경우, 하위작업이 있는 작업은 작업자 선택이 안되고 하위작업에 참여중인 작업자를 모두 합하여 (중복되지않게) 보여주는 걸로 변경해."
    func effectiveAssigneeIds(for task: TaskItem) -> [UUID] {
        if task.children.isEmpty {
            return task.assigneeIds
        }
        var uniqueSet = Set<UUID>()
        func collect(items: [TaskItem]) {
            for item in items {
                uniqueSet.formUnion(item.assigneeIds)
                collect(items: item.children)
            }
        }
        collect(items: task.children)
        return Array(uniqueSet)
    }
    
    // MARK: - Bar Interactions & Resizing
    func updateTaskDates(id: UUID, newStartDate: Date, newEndDate: Date) {
        guard var task = findTask(id: id) else { return }
        recordUndo()
        let validStart = newStartDate.startOfDay
        let validEnd = task.isMilestone ? validStart : max(validStart, newEndDate.startOfDay)
        
        task.startDate = validStart
        task.endDate = validEnd
        updateTask(task)
        enforceDependencies(startingFrom: id)
    }
    
    func shiftTaskBar(id: UUID, daysDelta: Int) {
        guard daysDelta != 0, var task = findTask(id: id) else { return }
        recordUndo()
        task.startDate = task.startDate.addingDays(daysDelta)
        task.endDate = task.isMilestone ? task.startDate : task.endDate.addingDays(daysDelta)
        updateTask(task)
        enforceDependencies(startingFrom: id)
    }
    
    // MARK: - Keyboard Navigation & Tree Movement
    func selectPreviousTask() {
        guard !flattenedRows.isEmpty else { return }
        guard let currentId = selectedTaskId,
              let currentIndex = flattenedRows.firstIndex(where: { $0.id == currentId }) else {
            selectedTaskId = flattenedRows.last?.id
            return
        }
        let prevIndex = max(0, currentIndex - 1)
        selectedTaskId = flattenedRows[prevIndex].id
        ensureTaskVisible(index: prevIndex)
    }
    
    func selectNextTask() {
        guard !flattenedRows.isEmpty else { return }
        guard let currentId = selectedTaskId,
              let currentIndex = flattenedRows.firstIndex(where: { $0.id == currentId }) else {
            selectedTaskId = flattenedRows.first?.id
            return
        }
        let nextIndex = min(flattenedRows.count - 1, currentIndex + 1)
        selectedTaskId = flattenedRows[nextIndex].id
        ensureTaskVisible(index: nextIndex)
    }
    
    func ensureTaskVisible(index: Int) {
        let taskY = CGFloat(index) * rowHeight
        if taskY < scrollOffsetY {
            scrollOffsetY = taskY
        } else {
            let visibleRows = 10
            let approxViewportH = CGFloat(visibleRows) * rowHeight
            if taskY + rowHeight > scrollOffsetY + approxViewportH {
                scrollOffsetY = taskY + rowHeight - approxViewportH
            }
        }
    }
    
    func moveSelectedTaskUpInTree() {
        guard isTaskTreeManipulationAllowed,
              let selectedId = selectedTaskId,
              let currentIndex = flattenedRows.firstIndex(where: { $0.id == selectedId }) else { return }
        guard currentIndex > 0 else { return }
        
        let targetRow = flattenedRows[currentIndex - 1]
        moveTask(sourceId: selectedId, targetId: targetRow.id, location: .above)
        
        if let newIdx = flattenedRows.firstIndex(where: { $0.id == selectedId }) {
            ensureTaskVisible(index: newIdx)
        }
    }
    
    func moveSelectedTaskDownInTree() {
        guard isTaskTreeManipulationAllowed,
              let selectedId = selectedTaskId,
              let currentIndex = flattenedRows.firstIndex(where: { $0.id == selectedId }) else { return }
        
        // Find next non-descendant row
        let currentTaskRow = flattenedRows[currentIndex]
        var nextTargetIndex = currentIndex + 1
        while nextTargetIndex < flattenedRows.count && flattenedRows[nextTargetIndex].level > currentTaskRow.level {
            nextTargetIndex += 1
        }
        
        guard nextTargetIndex < flattenedRows.count else { return }
        let targetRow = flattenedRows[nextTargetIndex]
        
        if targetRow.hasChildren && targetRow.isExpanded {
            moveTask(sourceId: selectedId, targetId: targetRow.id, location: .inside)
        } else {
            moveTask(sourceId: selectedId, targetId: targetRow.id, location: .below)
        }
        
        if let newIdx = flattenedRows.firstIndex(where: { $0.id == selectedId }) {
            ensureTaskVisible(index: newIdx)
        }
    }
    
    func shiftSelectedTask(byDays days: Int) {
        guard let selectedId = selectedTaskId else { return }
        shiftTaskBar(id: selectedId, daysDelta: days)
    }
    
    // MARK: - Assignee Tasks Export Helpers
    func exportDateRange() -> (start: Date, end: Date) {
        let start = Date().startOfDay
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start.addingDays(30)
        return (start, end)
    }
    
    func filteredTasksForExport(assigneeId: UUID) -> [TaskItem] {
        let range = exportDateRange()
        func filter(items: [TaskItem]) -> [TaskItem] {
            return items.compactMap { task in
                let directMatch = task.assigneeIds.contains(assigneeId) &&
                    task.startDate.startOfDay <= range.end &&
                    task.effectiveEndDate.startOfDay >= range.start
                
                let filteredChildren = filter(items: task.children)
                
                if directMatch || !filteredChildren.isEmpty {
                    var copy = task
                    copy.children = filteredChildren
                    return copy
                }
                return nil
            }
        }
        return filter(items: project.tasks)
    }
    
    func flattenedExportRows(assigneeId: UUID) -> [ExportTaskRow] {
        let roots = filteredTasksForExport(assigneeId: assigneeId)
        var rows: [ExportTaskRow] = []
        func flatten(items: [TaskItem], level: Int) {
            for item in items {
                rows.append(ExportTaskRow(task: item, level: level))
                flatten(items: item.children, level: level + 1)
            }
        }
        flatten(items: roots, level: 0)
        return rows
    }
    
    func exportAllAssigneesTasks() {
        showExportAllAssigneesSheet = true
    }
    
    /// Generates individual Excel (.xlsx) files for each worker and compresses them into a single .zip file.
    /// Deletes individual worker Excel files after compression.
    /// For workers with English names, all content is translated and presented in parallel (bilingual).
    func executeAllAssigneesZipExport(
        destinationZipURL: URL,
        progressHandler: @escaping (String, Double) -> Void
    ) async throws -> Int {
        // Collect assignees that have at least one task in the 1-month range
        let targetAssignees = sortedAssignees.filter { assignee in
            !flattenedExportRows(assigneeId: assignee.id).isEmpty
        }
        guard !targetAssignees.isEmpty else {
            throw NSError(
                domain: "GanttLab",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "향후 1달 이내에 할당된 작업이 있는 작업자가 없습니다."]
            )
        }
        
        let dateSuffix = Date().formattedDateString.replacingOccurrences(of: "-", with: "")
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("GanttLab_AllWorkers_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        
        defer {
            // Always clean up individual worker excel files and temp folder
            try? FileManager.default.removeItem(at: tempFolder)
        }
        
        var generatedFileNames: [String] = []
        let total = Double(targetAssignees.count)
        
        for (index, assignee) in targetAssignees.enumerated() {
            let rows = flattenedExportRows(assigneeId: assignee.id)
            let progressBase = Double(index) / total
            
            var translatedTitles: [UUID: String] = [:]
            var translatedNotes: [UUID: String] = [:]
            
            if assignee.isEnglishName {
                progressHandler("\(assignee.name) 님의 할일 영문 번역 중...", progressBase + 0.1 / total)
                
                // Collect Korean texts to translate
                var textsToTranslate = Set<String>()
                for r in rows {
                    let title = r.task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty && title.range(of: "\\p{Hangul}", options: .regularExpression) != nil {
                        textsToTranslate.insert(title)
                    }
                    let notes = r.task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty && notes.range(of: "\\p{Hangul}", options: .regularExpression) != nil {
                        textsToTranslate.insert(notes)
                    }
                }
                
                let translations = await TranslationService.shared.translateBatch(Array(textsToTranslate))
                for r in rows {
                    let titleTrimmed = r.task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let trans = translations[titleTrimmed] {
                        translatedTitles[r.task.id] = trans
                    }
                    let notesTrimmed = r.task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notesTrimmed.isEmpty, let transNotes = translations[notesTrimmed] {
                        translatedNotes[r.task.id] = transNotes
                    }
                }
            }
            
            progressHandler("\(assignee.name) 님의 엑셀 파일 생성 중...", progressBase + 0.6 / total)
            
            let safeName = sanitizeExportFileName(assignee.name)
            let fileName = "\(safeName)_할일목록_\(dateSuffix).xlsx"
            let fileURL = tempFolder.appendingPathComponent(fileName)
            
            try ExcelExporter.exportTasks(
                assignee: assignee,
                project: project,
                exportRows: rows,
                destinationURL: fileURL,
                translatedTitles: translatedTitles,
                translatedNotes: translatedNotes
            )
            
            generatedFileNames.append(fileName)
        }
        
        progressHandler("ZIP 압축 파일 생성 중...", 0.92)
        
        // Remove pre-existing destination file if any
        if FileManager.default.fileExists(atPath: destinationZipURL.path) {
            try FileManager.default.removeItem(at: destinationZipURL)
        }
        
        // Compress using macOS built-in /usr/bin/ditto (perfect UTF-8 / Korean filename support)
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipProcess.arguments = ["-c", "-k", "--sequesterRsrc", tempFolder.path, destinationZipURL.path]
        try zipProcess.run()
        zipProcess.waitUntilExit()
        
        if zipProcess.terminationStatus != 0 {
            throw NSError(
                domain: "GanttLab",
                code: Int(zipProcess.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ZIP 파일 압축에 실패했습니다. (종료 코드: \(zipProcess.terminationStatus))"]
            )
        }
        
        progressHandler("완료", 1.0)
        return targetAssignees.count
    }
    
    private func sanitizeExportFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    // MARK: - Dependency Connection & Toggle (Shift-Click)
    func rawUpdateTask(_ updated: TaskItem) {
        func update(items: inout [TaskItem]) -> Bool {
            for i in 0..<items.count {
                if items[i].id == updated.id {
                    items[i] = updated
                    return true
                }
                if update(items: &items[i].children) {
                    return true
                }
            }
            return false
        }
        _ = update(items: &project.tasks)
    }

    func handleBarShiftClick(fromTaskId: UUID, toTaskId: UUID) {
        guard fromTaskId != toTaskId else { return }
        guard let taskA = findTask(id: fromTaskId),
              let taskB = findTask(id: toTaskId) else { return }
        
        // "하위작업이 있는 작업의 경우 다른 작업과 연결되지 않도록 해. 하위 작업이 없는 작업 끼리면 연결하도록 하고."
        guard taskA.children.isEmpty && taskB.children.isEmpty else {
            NSSound.beep()
            return
        }
        
        recordUndo()
        
        let earlierTask: TaskItem
        let laterTask: TaskItem
        if taskA.effectiveEndDate <= taskB.effectiveEndDate {
            earlierTask = taskA
            laterTask = taskB
        } else {
            earlierTask = taskB
            laterTask = taskA
        }
        
        if let existingIndex = project.dependencies.firstIndex(where: {
            ($0.fromTaskId == earlierTask.id && $0.toTaskId == laterTask.id) ||
            ($0.fromTaskId == laterTask.id && $0.toTaskId == earlierTask.id)
        }) {
            project.dependencies.remove(at: existingIndex)
            invalidateCache()
        } else {
            let dep = Dependency(fromTaskId: earlierTask.id, toTaskId: laterTask.id)
            project.dependencies.append(dep)
            enforceDependencies(startingFrom: earlierTask.id)
        }
    }
    
    /// "하위작업이 있는 작업의 경우 다른 작업과 연결되지 않도록 해. 만약 이전에 하위작업이 없었는데 새로 하위 작업이 생겼다면 기존의 연결을 제거하도록 해."
    func cleanParentDependencies() {
        let all = getAllTasksFlat()
        let parentIds = Set(all.filter { !$0.children.isEmpty }.map { $0.id })
        guard !parentIds.isEmpty else { return }
        let beforeCount = project.dependencies.count
        project.dependencies.removeAll { parentIds.contains($0.fromTaskId) || parentIds.contains($0.toTaskId) }
        if project.dependencies.count != beforeCount {
            invalidateCache()
        }
    }
    
    /// Safe dependency cascading: pushes downstream tasks without infinite loops or crashes
    func enforceDependencies(startingFrom rootId: UUID) {
        var queue = [rootId]
        var visited = Set<UUID>()
        var iterations = 0
        let maxIterations = 200 // Safety guard against cycles
        
        while !queue.isEmpty && iterations < maxIterations {
            iterations += 1
            let currentId = queue.removeFirst()
            guard let currentTask = findTask(id: currentId) else { continue }
            
            let outgoing = project.dependencies.filter { $0.fromTaskId == currentId }
            for dep in outgoing {
                guard var nextTask = findTask(id: dep.toTaskId) else { continue }
                let currentEnd = currentTask.effectiveEndDate
                let nextStart = nextTask.effectiveStartDate
                
                if currentEnd >= nextStart {
                    let requiredStart = currentEnd.addingDays(1)
                    let shiftDays = nextStart.daysBetween(requiredStart)
                    
                    if shiftDays > 0 {
                        if nextTask.children.isEmpty {
                            let duration = nextTask.isMilestone ? 1 : max(1, nextTask.startDate.daysBetween(nextTask.endDate) + 1)
                            nextTask.startDate = requiredStart
                            nextTask.endDate = nextTask.isMilestone ? requiredStart : requiredStart.addingDays(duration - 1)
                            rawUpdateTask(nextTask)
                        } else {
                            // Parent task: shift its children recursively so its effectiveStartDate moves forward!
                            nextTask.shiftDatesRecursively(days: shiftDays)
                            rawUpdateTask(nextTask)
                        }
                        
                        if !visited.contains(nextTask.id) {
                            visited.insert(nextTask.id)
                            queue.append(nextTask.id)
                        }
                    }
                }
            }
        }
        
        syncHierarchy()
        invalidateCache()
    }
    
    // MARK: - Hierarchy Synchronization (Parent Dates & Completion Status)
    /// 1. "하위 작업이 모두 완료라면 바로 윗 상위 작업도 완료 표시로 변경하도록 해"
    /// 2. "Gantt Chart에서 하위작업이 있는 작업의 경우, 기간은 모든 하위작업의 첫 시작부터 모든 하위작업의 제일 늦은 종료시점이어야 해."
    /// 3. "만약 이전에 하위작업이 없었는데 새로 하위 작업이 생겼다면 기존의 연결을 제거하도록 해."
    func syncHierarchy() {
        cleanParentDependencies()
        func processNode(node: inout TaskItem) -> (allCompleted: Bool, minStart: Date, maxEnd: Date) {
            if node.children.isEmpty {
                return (node.isCompleted, node.startDate, node.endDate)
            }
            
            var allCompleted = true
            var minStart: Date? = nil
            var maxEnd: Date? = nil
            
            for i in 0..<node.children.count {
                let res = processNode(node: &node.children[i])
                if !res.allCompleted {
                    allCompleted = false
                }
                if minStart == nil || res.minStart < minStart! {
                    minStart = res.minStart
                }
                if maxEnd == nil || res.maxEnd > maxDate(maxEnd, res.maxEnd) {
                    maxEnd = res.maxEnd
                }
            }
            
            node.isCompleted = allCompleted
            if let start = minStart, let end = maxEnd {
                node.startDate = start
                node.endDate = max(start, end)
            }
            
            return (node.isCompleted, node.startDate, node.endDate)
        }
        
        func maxDate(_ d1: Date?, _ d2: Date) -> Date {
            guard let d1 = d1 else { return d2 }
            return d1 > d2 ? d1 : d2
        }
        
        for i in 0..<project.tasks.count {
            _ = processNode(node: &project.tasks[i])
        }
    }

    // MARK: - Detail Sheet Adjustments
    /// "작업 세부설정에서 -1일 단축이나 +1일 연장을 누르면 연결된 작업만 같이 기간이 조정되어야 하는데"
    func adjustTaskDuration(id: UUID, byDays days: Int) {
        guard var task = findTask(id: id) else { return }
        // If task has children or is a milestone, its duration cannot be adjusted!
        guard task.children.isEmpty, !task.isMilestone else { return }
        
        let newEnd = task.endDate.addingDays(days)
        guard newEnd >= task.startDate else { return }
        recordUndo()
        
        task.endDate = newEnd
        // DO NOT modify task.children dates! Only update this task.
        updateTask(task)
        
        // Cascade only to connected dependencies!
        enforceDependencies(startingFrom: id)
        
        // Sync parent dates & completion
        syncHierarchy()
        invalidateCache()
        
        if detailTask?.id == id {
            detailTask = findTask(id: id)
        }
    }
    
    func setTaskColorRecursively(id: UUID, hex: String) {
        guard var task = findTask(id: id) else { return }
        recordUndo()
        task.applyColorRecursively(hex)
        updateTask(task)
        if detailTask?.id == id {
            detailTask = findTask(id: id)
        }
    }
    
    // MARK: - Assignee Management
    func addAssignee(name: String, avatarData: Data? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newAssignee = Assignee(name: trimmed, avatarData: avatarData)
        project.assignees.append(newAssignee)
        project.assignees.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        invalidateCache()
    }
    
    func deleteAssignee(id: UUID) {
        project.assignees.removeAll { $0.id == id }
        func removeFromTasks(items: inout [TaskItem]) {
            for i in 0..<items.count {
                items[i].assigneeIds.removeAll { $0 == id }
                removeFromTasks(items: &items[i].children)
            }
        }
        removeFromTasks(items: &project.tasks)
        invalidateCache()
    }
    
    func updateAssignee(_ assignee: Assignee) {
        if let idx = project.assignees.firstIndex(where: { $0.id == assignee.id }) {
            project.assignees[idx] = assignee
            project.assignees.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            invalidateCache()
        }
    }
    
    var sortedAssignees: [Assignee] {
        project.assignees.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Ultra-Fast O(1) Workload Cache
    // Builds map once when project data changes. Every cell lookup is O(1) instantaneous!
    // 키는 타임라인 시작일 기준 날짜 인덱스(Int)이므로 날짜→문자열 변환이 필요 없다.
    private func buildWorkloadMapIfNeeded() {
        if _cachedWorkloadMap != nil,
           _workloadMapBaseStart == timelineStartDate,
           _workloadMapBaseTotal == timelineTotalDays {
            return
        }
        var map: [UUID: [Int: Int]] = [:]
        for assignee in project.assignees {
            map[assignee.id] = [:]
        }
        
        let allTasks = getAllTasksFlat()
        let start = timelineStartDate
        let total = timelineTotalDays
        
        for task in allTasks {
            guard !task.assigneeIds.isEmpty else { continue }
            let startIndex = max(0, start.daysBetween(task.startDate))
            let endIndex = min(total, start.daysBetween(task.endDate))
            
            if startIndex <= endIndex {
                for dayIndex in startIndex...endIndex {
                    for assigneeId in task.assigneeIds {
                        map[assigneeId, default: [:]][dayIndex, default: 0] += 1
                    }
                }
            }
        }
        _cachedWorkloadMap = map
        _workloadMapBaseStart = start
        _workloadMapBaseTotal = total
    }
    
    /// 타임라인 날짜 인덱스 기준 작업 수 조회 (워크로드 셀 전용, O(1))
    func activeTaskCount(for assigneeId: UUID, dayIndex: Int) -> Int {
        buildWorkloadMapIfNeeded()
        return _cachedWorkloadMap?[assigneeId]?[dayIndex] ?? 0
    }
    
    func activeTaskCount(for assigneeId: UUID, on date: Date) -> Int {
        activeTaskCount(for: assigneeId, dayIndex: timelineStartDate.daysBetween(date))
    }
    
    // MARK: - Workload Filter & Inspection
    func toggleWorkloadFilter(assigneeId: UUID, date: Date) {
        if let current = selectedWorkloadFilter,
           current.assigneeId == assigneeId,
           Calendar.current.isDate(current.date, inSameDayAs: date) {
            clearWorkloadFilter()
            return
        }
        applyWorkloadFilter(assigneeId: assigneeId, date: date)
    }
    
    func clearWorkloadFilter() {
        guard selectedWorkloadFilter != nil else { return }
        selectedWorkloadFilter = nil
        invalidateCache()
    }
    
    func isAssigneeIncluded(assigneeId: UUID, in task: TaskItem) -> Bool {
        return effectiveAssigneeIds(for: task).contains(assigneeId)
    }
    
    /// 특정 작업(또는 그 하위 작업)이 현재 선택된 워크로드 필터(특정 작업자 + 특정 날짜)에 매칭되는지 판정
    func isTaskMatchingWorkloadFilter(task: TaskItem) -> Bool {
        guard let filter = selectedWorkloadFilter else { return true }
        let targetDay = filter.date.startOfDay
        let assigneeId = filter.assigneeId
        return isTaskOrDescendantMatchingWorkload(task: task, assigneeId: assigneeId, targetDay: targetDay)
    }
    
    private func isTaskOrDescendantMatchingWorkload(task: TaskItem, assigneeId: UUID, targetDay: Date) -> Bool {
        // 1. 해당 작업 자체에 작업자가 배정되어 있고, 날짜 범위(시작일~종료일) 내에 targetDay가 포함되는지
        let isDirectMatch = task.assigneeIds.contains(assigneeId) &&
                            task.startDate.startOfDay <= targetDay &&
                            targetDay <= task.endDate.startOfDay
        if isDirectMatch {
            return true
        }
        
        // 2. 상위 작업의 경우 하위 자식들 중 매칭되는 작업이 있는지 재귀 확인
        for child in task.children {
            if isTaskOrDescendantMatchingWorkload(task: child, assigneeId: assigneeId, targetDay: targetDay) {
                return true
            }
        }
        
        return false
    }
    
    /// 현재 워크로드 필터가 활성화된 상태에서, 해당 날짜에 해당 작업자가 속하지 않은 모든 작업을 반투명(Dimmed) 처리
    func isTaskDimmedByWorkloadFilter(task: TaskItem) -> Bool {
        guard selectedWorkloadFilter != nil else { return false }
        return !isTaskMatchingWorkloadFilter(task: task)
    }
    
    func applyWorkloadFilter(assigneeId: UUID, date: Date) {
        let targetDay = date.startOfDay
        let wasDirty = self.isDirty
        
        // 1. 모든 작업 트리를 접고
        func collapseAll(items: inout [TaskItem]) {
            for i in 0..<items.count {
                items[i].isExpanded = false
                collapseAll(items: &items[i].children)
            }
        }
        collapseAll(items: &project.tasks)
        
        // 2. 해당 날짜에 해당 작업자가 속한 작업 수집
        var matchingIds = Set<UUID>()
        func collectMatching(items: [TaskItem]) {
            for item in items {
                let hasAssignee = item.assigneeIds.contains(assigneeId)
                let inDateRange = item.startDate.startOfDay <= targetDay && targetDay <= item.endDate.startOfDay
                if hasAssignee && inDateRange {
                    matchingIds.insert(item.id)
                }
                collectMatching(items: item.children)
            }
        }
        collectMatching(items: project.tasks)
        
        // 3. 해당 날짜에 해당 작업자가 속한 작업의 상위 경로 및 작업 펼치기
        @discardableResult
        func expandMatchingAncestors(items: inout [TaskItem]) -> Bool {
            var branchHasMatch = false
            for i in 0..<items.count {
                let isSelfMatch = matchingIds.contains(items[i].id)
                let childHasMatch = expandMatchingAncestors(items: &items[i].children)
                if isSelfMatch || childHasMatch {
                    items[i].isExpanded = true
                    branchHasMatch = true
                }
            }
            return branchHasMatch
        }
        expandMatchingAncestors(items: &project.tasks)
        
        self.isDirty = wasDirty
        self.selectedWorkloadFilter = WorkloadFilterState(assigneeId: assigneeId, date: targetDay)
        invalidateCache()
    }
    
    // MARK: - File Operations (New, Open, Save, Save As)
    func requestNewProject() {
        if isDirty {
            showUnsavedAlert = true
            pendingNewProjectAction = { [weak self] in
                self?.resetToNewProject()
            }
        } else {
            resetToNewProject()
        }
    }
    
    func resetToNewProject() {
        isSuppressedDirty = true
        defer {
            isSuppressedDirty = false
            self.isDirty = false
            clearUndoHistory()
            updateMainWindowRepresentation()
        }
        
        self.project = ProjectData(
            version: "1.0",
            title: "새 프로젝트",
            tasks: [],
            dependencies: [],
            assignees: Assignee.defaultAssignees.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
        self.currentFileURL = nil
        self.selectedTaskId = nil
        self.editingTaskId = nil
        self.editingTitle = ""
        self.detailTask = nil
        self.assigneeManagerTaskId = nil
        self.selectedWorkloadFilter = nil
        UserDefaults.standard.removeObject(forKey: "LastSavedProjectFilePath")
        clearUndoHistory()
        invalidateCache()
        scrollToToday(offsetDaysFromLeft: 2)
    }
    
    func saveProject() {
        if let url = currentFileURL {
            _ = writeProjectSynchronously(to: url)
        } else {
            saveProjectAs()
        }
    }
    
    func saveProjectAs(completion: ((Bool) -> Void)? = nil) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        var baseName = project.title
        if !baseName.hasSuffix(".ganttlab") {
            baseName += ".ganttlab"
        }
        savePanel.nameFieldStringValue = baseName
        savePanel.allowedContentTypes = [Self.ganttLabType, .json]
        
        savePanel.begin { [weak self] response in
            guard let self = self else {
                completion?(false)
                return
            }
            if response == .OK, let url = savePanel.url {
                let success = self.writeProjectSynchronously(to: url)
                completion?(success)
            } else {
                completion?(false)
            }
        }
    }
    
    @discardableResult
    func writeProjectSynchronously(to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(project)
            
            // "용량문제가 생길 수 있다면 저장 파일을 압축파일 형태로 만들고, 확장자를 ganttlab 이라고 해."
            let compressedData = try (jsonData as NSData).compressed(using: .zlib) as Data
            try compressedData.write(to: url, options: .atomic)
            self.currentFileURL = url
            self.isDirty = false
            UserDefaults.standard.set(url.path, forKey: "LastSavedProjectFilePath")
            return true
        } catch {
            print("Failed to save project: \(error)")
            let alert = NSAlert()
            alert.messageText = "저장 실패"
            alert.informativeText = "파일을 저장하는 중 오류가 발생했습니다: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "확인")
            alert.runModal()
            return false
        }
    }
    
    func openProject() {
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "저장되지 않은 변경사항"
            alert.informativeText = "'\(project.title)' 프로젝트의 변경 내용을 저장하지 않고 새 프로젝트를 여시겠습니까?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "저장 후 열기")
            alert.addButton(withTitle: "저장하지 않고 열기")
            alert.addButton(withTitle: "취소")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Save first
                if let url = currentFileURL {
                    if !writeProjectSynchronously(to: url) { return }
                } else {
                    let savePanel = NSSavePanel()
                    savePanel.canCreateDirectories = true
                    var baseName = project.title
                    if !baseName.hasSuffix(".ganttlab") {
                        baseName += ".ganttlab"
                    }
                    savePanel.nameFieldStringValue = baseName
                    savePanel.allowedContentTypes = [Self.ganttLabType, .json]
                    if savePanel.runModal() == .OK, let url = savePanel.url {
                        if !writeProjectSynchronously(to: url) { return }
                    } else {
                        return
                    }
                }
            } else if response == .alertThirdButtonReturn {
                return
            }
        }
        
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [Self.ganttLabType, .json]
        
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = openPanel.url {
                self.loadProject(from: url)
            }
            // Bring main window to front and activate app!
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            }
        }
    }
    
    func loadProject(from url: URL, isAutoLoad: Bool = false) {
        isSuppressedDirty = true
        defer {
            isSuppressedDirty = false
            self.isDirty = false
            clearUndoHistory()
            updateMainWindowRepresentation()
        }
        
        do {
            let rawData = try Data(contentsOf: url)
            
            // Decompress if zlib compressed; fallback to raw data if uncompressed JSON
            let jsonData: Data
            if let decompressed = try? (rawData as NSData).decompressed(using: .zlib) as Data {
                jsonData = decompressed
            } else {
                jsonData = rawData
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded = try decoder.decode(ProjectData.self, from: jsonData)
            loaded.assignees.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.project = loaded
            self.currentFileURL = url
            self.selectedTaskId = nil
            self.editingTaskId = nil
            self.editingTitle = ""
            self.detailTask = nil
            self.assigneeManagerTaskId = nil
            clearUndoHistory()
            syncHierarchy()
            invalidateCache()
            scrollToToday(offsetDaysFromLeft: 2)
            UserDefaults.standard.set(url.path, forKey: "LastSavedProjectFilePath")
            
            // 1. Create backup on load/launch as specified
            self.createBackup(for: url)
            
            // 2. Verify attachment integrity & clean up broken links/orphans
            let report = self.verifyAttachmentsIntegrity(for: url)
            if report.hasChanges {
                DispatchQueue.main.async {
                    self.attachmentReport = report
                }
            }
            
            // 3. Show uncompleted milestones window only if manually opened.
            // On auto-load at app launch, MainView.onAppear will handle it safely after the main window is visible.
            if !isAutoLoad {
                self.checkAndShowUnfinishedMilestones()
            }
            
            // Ensure project is clean right after opening!
            self.isDirty = false
            clearUndoHistory()
            
            // Bring main window to front and activate app!
            DispatchQueue.main.async {
                self.isDirty = false
                self.updateMainWindowRepresentation()
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            }
        } catch {
            print("Failed to load project: \(error)")
            if isAutoLoad {
                UserDefaults.standard.removeObject(forKey: "LastSavedProjectFilePath")
                self.project = ProjectData.createSampleProject()
                self.project.assignees.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.currentFileURL = nil
                self.isDirty = false
                syncHierarchy()
                invalidateCache()
                scrollToToday(offsetDaysFromLeft: 2)
            } else {
                let alert = NSAlert()
                alert.messageText = "파일 열기 실패"
                alert.informativeText = "프로젝트 파일을 읽는 중 오류가 발생했습니다: \(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "확인")
                alert.runModal()
            }
        }
    }
    
    // MARK: - Quit/Close Save Prompt (Handles Cmd-Q, Cmd-X, Window Close)
    /// Returns true if app can quit/close, false if cancelled
    func confirmSaveBeforeClosing() -> Bool {
        guard isDirty else { return true }
        
        let alert = NSAlert()
        alert.messageText = "저장되지 않은 변경사항"
        alert.informativeText = "'\(project.title)' 프로젝트의 변경 내용을 종료하기 전에 저장하시겠습니까?\n저장하지 않으면 작업한 내용이 모두 손실됩니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "저장 안 함")
        alert.addButton(withTitle: "취소")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Save
            if let url = currentFileURL {
                let success = writeProjectSynchronously(to: url)
                if success {
                    self.isDirty = false
                    return true
                }
                return false
            } else {
                let savePanel = NSSavePanel()
                savePanel.canCreateDirectories = true
                savePanel.showsTagField = false
                var baseName = project.title
                if !baseName.hasSuffix(".ganttlab") {
                    baseName += ".ganttlab"
                }
                savePanel.nameFieldStringValue = baseName
                savePanel.allowedContentTypes = [Self.ganttLabType, .json]
                
                let saveResponse = savePanel.runModal()
                if saveResponse == .OK, let url = savePanel.url {
                    let success = writeProjectSynchronously(to: url)
                    if success {
                        self.isDirty = false
                        return true
                    }
                    return false
                } else {
                    return false // User cancelled save panel -> cancel quit
                }
            }
        } else if response == .alertSecondButtonReturn {
            // Don't save -> proceed with quit/close
            self.isDirty = false
            return true
        } else {
            // Cancel -> abort quit/close
            return false
        }
    }
    
    // MARK: - Milestone Management
    @discardableResult
    func setTaskMilestone(id: UUID, isMilestone: Bool) -> Bool {
        guard var task = findTask(id: id) else { return false }
        if isMilestone {
            if !task.children.isEmpty {
                let alert = NSAlert()
                alert.messageText = "마일스톤 전환 불가"
                alert.informativeText = "하위 작업이 있는 작업은 마일스톤으로 전환할 수 없습니다."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "확인")
                alert.runModal()
                return false
            }
            recordUndo()
            task.isMilestone = true
            task.endDate = task.startDate
            updateTask(task)
            enforceDependencies(startingFrom: id)
            return true
        } else {
            recordUndo()
            task.isMilestone = false
            updateTask(task)
            enforceDependencies(startingFrom: id)
            return true
        }
    }
    
    // MARK: - Attachments & Folder Paths
    func projectFolderURL() -> URL? {
        guard let fileURL = currentFileURL else { return nil }
        let parentDir = fileURL.deletingLastPathComponent()
        let projectFolderName = fileURL.deletingPathExtension().lastPathComponent
        return parentDir.appendingPathComponent(projectFolderName, isDirectory: true)
    }
    
    func attachmentsDirectoryURL() -> URL? {
        guard let projDir = projectFolderURL() else { return nil }
        return projDir.appendingPathComponent("Attachments", isDirectory: true)
    }
    
    func backupDirectoryURL() -> URL? {
        guard let projDir = projectFolderURL() else { return nil }
        return projDir.appendingPathComponent("backup", isDirectory: true)
    }
    
    func resolveUniqueAttachmentFileName(for name: String, in dir: URL) -> String {
        let fileManager = FileManager.default
        let ext = (name as NSString).pathExtension
        let rawStem = (name as NSString).deletingPathExtension
        
        let initialURL = dir.appendingPathComponent(name)
        if !fileManager.fileExists(atPath: initialURL.path) {
            return name
        }
        
        var baseStem = rawStem
        var startNum = 1
        
        let pattern = "^(.*?)(?:\\s+(\\d+))$"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: rawStem, range: NSRange(location: 0, length: rawStem.utf16.count)) {
            if let baseRange = Range(match.range(at: 1), in: rawStem),
               let numRange = Range(match.range(at: 2), in: rawStem) {
                let matchedBase = String(rawStem[baseRange])
                if let parsedNum = Int(String(rawStem[numRange])) {
                    baseStem = matchedBase
                    startNum = parsedNum + 1
                }
            }
        }
        
        var counter = startNum
        while true {
            let candidateName = ext.isEmpty ? "\(baseStem) \(counter)" : "\(baseStem) \(counter).\(ext)"
            let candidateURL = dir.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateName
            }
            counter += 1
        }
    }
    
    @discardableResult
    func addAttachment(from sourceURL: URL, toTaskId taskId: UUID) -> TaskAttachment? {
        guard var targetTask = findTask(id: taskId) else { return nil }
        
        if currentFileURL == nil {
            let alert = NSAlert()
            alert.messageText = "프로젝트 저장 필요"
            alert.informativeText = "파일을 첨부하려면 먼저 프로젝트를 저장해야 합니다.\n지금 프로젝트를 저장하시겠습니까?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "저장하기")
            alert.addButton(withTitle: "취소")
            let res = alert.runModal()
            if res == .alertFirstButtonReturn {
                var saved = false
                saveProjectAs { success in
                    saved = success
                }
                if !saved || currentFileURL == nil {
                    return nil
                }
            } else {
                return nil
            }
        }
        
        guard let attachmentsDir = attachmentsDirectoryURL() else { return nil }
        
        do {
            try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create Attachments directory: \(error)")
            return nil
        }
        
        let values = try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey])
        let fileDate = values?.contentModificationDate ?? values?.creationDate ?? Date()
        let fileSize = Int64(values?.fileSize ?? 0)
        let originalName = sourceURL.lastPathComponent
        
        let destFileName = resolveUniqueAttachmentFileName(for: originalName, in: attachmentsDir)
        let destURL = attachmentsDir.appendingPathComponent(destFileName)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("Failed to copy attachment: \(error)")
            return nil
        }
        
        let newAttachment = TaskAttachment(
            fileName: destFileName,
            originalName: originalName,
            fileDate: fileDate,
            fileSize: fileSize
        )
        
        recordUndo()
        targetTask.attachments.append(newAttachment)
        targetTask.attachments.sort { $0.fileDate > $1.fileDate }
        updateTask(targetTask)
        
        return newAttachment
    }
    
    func removeAttachment(attachmentId: UUID, fromTaskId taskId: UUID) {
        guard var task = findTask(id: taskId) else { return }
        guard let att = task.attachments.first(where: { $0.id == attachmentId }) else { return }
        
        recordUndo()
        task.attachments.removeAll(where: { $0.id == attachmentId })
        updateTask(task)
        
        // Check if any other task still references this file
        let allTasks = getAllTasksFlat()
        let stillReferenced = allTasks.contains { $0.attachments.contains(where: { $0.fileName == att.fileName }) }
        if !stillReferenced, let attachmentsDir = attachmentsDirectoryURL() {
            let fileURL = attachmentsDir.appendingPathComponent(att.fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    func openAttachment(_ attachment: TaskAttachment) {
        guard let attachmentsDir = attachmentsDirectoryURL() else { return }
        let fileURL = attachmentsDir.appendingPathComponent(attachment.fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.open(fileURL)
        } else {
            let alert = NSAlert()
            alert.messageText = "파일을 찾을 수 없음"
            alert.informativeText = "첨부파일 '\(attachment.fileName)'이(가) Attachments 폴더에 존재하지 않습니다."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
    }
    
    // MARK: - Integrity Check on Project Load
    func verifyAttachmentsIntegrity(for fileURL: URL) -> AttachmentIntegrityReport {
        var report = AttachmentIntegrityReport()
        let parentDir = fileURL.deletingLastPathComponent()
        let projectFolderName = fileURL.deletingPathExtension().lastPathComponent
        let projectDir = parentDir.appendingPathComponent(projectFolderName, isDirectory: true)
        let attachmentsDir = projectDir.appendingPathComponent("Attachments", isDirectory: true)
        
        let fileManager = FileManager.default
        let attachmentsDirExists = fileManager.fileExists(atPath: attachmentsDir.path)
        
        let diskFiles: Set<String>
        if attachmentsDirExists {
            let contents = (try? fileManager.contentsOfDirectory(atPath: attachmentsDir.path)) ?? []
            diskFiles = Set(contents.filter { $0 != ".DS_Store" })
        } else {
            diskFiles = Set()
        }
        
        var referencedFiles = Set<String>()
        
        func checkTaskTree(items: inout [TaskItem]) -> Bool {
            var modified = false
            for i in 0..<items.count {
                let originalCount = items[i].attachments.count
                var validAttachments: [TaskAttachment] = []
                for att in items[i].attachments {
                    if diskFiles.contains(att.fileName) {
                        validAttachments.append(att)
                        referencedFiles.insert(att.fileName)
                    } else {
                        report.removedBrokenLinks.append((taskTitle: items[i].title, fileName: att.fileName))
                    }
                }
                if validAttachments.count != originalCount {
                    items[i].attachments = validAttachments
                    modified = true
                }
                if checkTaskTree(items: &items[i].children) {
                    modified = true
                }
            }
            return modified
        }
        
        let tasksModified = checkTaskTree(items: &self.project.tasks)
        
        // Check for orphan files on disk
        if attachmentsDirExists {
            for diskFile in diskFiles {
                if !referencedFiles.contains(diskFile) {
                    let orphanURL = attachmentsDir.appendingPathComponent(diskFile)
                    do {
                        try fileManager.removeItem(at: orphanURL)
                        report.removedOrphanFiles.append(diskFile)
                    } catch {
                        print("Failed to remove orphan attachment file \(diskFile): \(error)")
                    }
                }
            }
        }
        
        if tasksModified {
            syncHierarchy()
            invalidateCache()
        }
        
        return report
    }
    
    // MARK: - Backup
    func createBackup(for fileURL: URL) {
        let parentDir = fileURL.deletingLastPathComponent()
        let projectFolderName = fileURL.deletingPathExtension().lastPathComponent
        let projectDir = parentDir.appendingPathComponent(projectFolderName, isDirectory: true)
        let backupDir = projectDir.appendingPathComponent("backup", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            let backupFileName = "\(timestamp).ganttlab"
            let backupDestinationURL = backupDir.appendingPathComponent(backupFileName)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if !FileManager.default.fileExists(atPath: backupDestinationURL.path) {
                    try FileManager.default.copyItem(at: fileURL, to: backupDestinationURL)
                    print("백업 생성 완료: \(backupDestinationURL.path)")
                }
            }
            
            // 1달이 지난 백업 파일 정리
            cleanOldBackups(in: backupDir)
        } catch {
            print("Failed to create backup: \(error)")
        }
    }
    
    /// backup 폴더 내 1달이 지난 백업 파일을 검색하여 삭제
    func cleanOldBackups(in backupDir: URL) {
        let fileManager = FileManager.default
        guard let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return }
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: backupDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            
            for file in files {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                
                let ext = file.pathExtension.lowercased()
                guard ext == "ganttlab" || ext == "json" else { continue }
                
                let rawStem = file.deletingPathExtension().lastPathComponent
                var fileDate: Date? = dateFormatter.date(from: rawStem)
                
                if fileDate == nil {
                    if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) {
                        fileDate = values.contentModificationDate ?? values.creationDate
                    }
                }
                
                if let date = fileDate, date < oneMonthAgo {
                    do {
                        try fileManager.removeItem(at: file)
                        print("1달 지난 백업 삭제 완료: \(file.lastPathComponent) (생성일자: \(date))")
                    } catch {
                        print("1달 지난 백업 삭제 실패 (\(file.lastPathComponent)): \(error)")
                    }
                }
            }
        } catch {
            print("Failed to clean old backups in \(backupDir.path): \(error)")
        }
    }
    
    // MARK: - Auto-Save (Every 10 minutes)
    func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 600.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isDirty, let url = self.currentFileURL {
                    print("10분 주기 자동 저장 실행: \(url.lastPathComponent)")
                    _ = self.writeProjectSynchronously(to: url)
                }
            }
        }
    }
    
    // MARK: - Unfinished Milestones Window
    func checkAndShowUnfinishedMilestones() {
        let all = getAllTasksFlat()
        let uncompleted = all.filter { $0.isMilestone && !$0.isCompleted }
        if !uncompleted.isEmpty {
            DispatchQueue.main.async {
                UnfinishedMilestonesWindowManager.shared.show(store: self)
            }
        }
    }
}


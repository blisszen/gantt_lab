import SwiftUI
import AppKit

/// Gantt 캔버스 뷰포트의 좌표계 이름. (스크롤 오프셋과 무관하게 고정된 좌표계)
/// 드래그 제스처를 이 좌표계로 측정하면, 움직이는 Bar 자신의 좌표계로 측정할 때 생기는
/// 이동량 흔들림을 피할 수 있고, 시작 위치가 곧 "뷰포트 내 X 좌표"가 된다.
enum GanttCanvasSpace {
    static let name = "GanttCanvasViewport"
}

struct GanttTimelineView: View {
    @ObservedObject var store: ProjectStore
    
    var body: some View {
        GeometryReader { geo in
            let scroll = store.scroll
            let visibleWidth = geo.size.width
            let visibleHeight = geo.size.height
            let scrollBarHeight: CGFloat = 14.0
            let scrollBarWidth: CGFloat = 14.0
            let canvasHeight = max(100.0, visibleHeight - store.headerHeight - 1.0 - scrollBarHeight)
            
            let totalContentHeight = CGFloat(store.flattenedRows.count + 1) * store.rowHeight
            let maxOffsetY = max(0, totalContentHeight - canvasHeight)
            let hasVerticalBar = maxOffsetY > 0
            let rightBarWidth: CGFloat = hasVerticalBar ? scrollBarWidth : 0
            let canvasAreaWidth = max(50.0, visibleWidth - rightBarWidth)
            
            // Calculate total canvas width to cover visible width + scroll offset + buffer.
            // 스크롤 오프셋 대신 "현재 가로 구간의 상한값"을 사용하여, 구간이 바뀔 때만 재계산되도록 한다.
            // (항상 실제 오프셋 이상이므로 스크롤 가능 범위는 기존과 같거나 더 넓다)
            let daysNeeded = Int(ceil((canvasAreaWidth + scroll.xBucketUpperBound) / store.dayWidth)) + 30
            let daysToRender = max(store.timelineTotalDays, daysNeeded)
            let totalCanvasWidth = max(CGFloat(daysToRender) * store.dayWidth, canvasAreaWidth + 1200)
            let maxOffsetX = max(0, totalCanvasWidth - canvasAreaWidth)
            
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    // 1. Timeline Date Header (Horizontally scrolled with scrollOffsetX)
                    ScrollOffsetView(scroll: scroll, horizontal: true) {
                        TimelineHeaderView(store: store, totalDays: daysToRender, viewportWidth: canvasAreaWidth)
                            .frame(width: totalCanvasWidth, height: store.headerHeight, alignment: .leading)
                    }
                    .frame(width: canvasAreaWidth, height: store.headerHeight, alignment: .leading)
                    .clipped()
                    
                    Divider()
                    
                    // 2. Timeline Canvas / Rows Area (2D Scrolled)
                    ZStack(alignment: .topLeading) {
                        // Background tap target (fixed to viewport, does not scroll)
                        Color.clear
                            .frame(width: canvasAreaWidth, height: canvasHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if store.editingTaskId != nil {
                                    store.commitInlineEditing()
                                }
                                store.clearWorkloadFilter()
                            }
                        
                        // Background Grid (shifts horizontally, only visible days are drawn)
                        ScrollOffsetView(scroll: scroll, horizontal: true) {
                            TimelineGridView(store: store, totalDays: daysToRender, viewportWidth: canvasAreaWidth)
                                .frame(width: totalCanvasWidth, height: canvasHeight, alignment: .topLeading)
                        }
                        .allowsHitTesting(false)
                        
                        // Dependency Arrows Layer (shifts in 2D)
                        ScrollOffsetView(scroll: scroll, horizontal: false, vertical: .none) {
                            DependencyArrowsView(store: store, canvasAreaWidth: canvasAreaWidth, canvasHeight: canvasHeight)
                                .frame(width: canvasAreaWidth, height: canvasHeight, alignment: .topLeading)
                        }
                        .allowsHitTesting(false)
                        
                        // Task Bars Layer (shifts in 2D, only visible rows are rendered)
                        ScrollOffsetView(scroll: scroll, horizontal: false, vertical: .gantt) {
                            GanttBarsLayer(
                                store: store,
                                totalDays: daysToRender,
                                canvasAreaWidth: canvasAreaWidth,
                                canvasHeight: canvasHeight,
                                totalCanvasWidth: totalCanvasWidth
                            )
                        }
                        
                        // Pan and Scroll Gesture Overlay:
                        // "Gantt Chart에서 마우스 우클릭을 한 상태에서 마우스를 옮기면 화면이 위아래 혹은 좌우 스크롤되도록 해."
                        PanAndScrollOverlay(
                            onScroll: { dx, dy in
                                store.scrollBy(deltaX: dx, deltaY: dy, maxOffsetX: maxOffsetX, maxOffsetY: maxOffsetY)
                            },
                            onRightPan: { dx, dy in
                                // Right mouse drag pan: in window coordinates, dy > 0 is up, dx > 0 is right
                                store.panScroll(
                                    deltaX: dx,
                                    deltaY: dy,
                                    maxOffsetX: maxOffsetX,
                                    maxOffsetY: maxOffsetY
                                )
                            }
                        )
                    }
                    .frame(width: canvasAreaWidth, height: canvasHeight, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .clipped()
                    .coordinateSpace(name: GanttCanvasSpace.name)
                    
                    // 3. Horizontal Scrollbar under Gantt Chart
                    // "Gantt Chart 화면 아래쪽에는 좌우 스크롤바를 넣고, 이를 기준으로 Gantt Chart와 작업자별 워크로드 날짜도 연동돼서 움직이도록 해."
                    HorizontalScrollBar(
                        offset: $store.scrollOffsetX,
                        maxOffset: maxOffsetX,
                        viewportWidth: canvasAreaWidth,
                        totalWidth: totalCanvasWidth
                    )
                    .frame(width: canvasAreaWidth, height: scrollBarHeight)
                }
                .frame(width: canvasAreaWidth)
                
                // 4. Vertical Scrollbar on the right edge of Gantt Chart!
                if hasVerticalBar {
                    VStack(spacing: 0) {
                        // Header spacer to align scrollbar below header
                        Color(NSColor.controlBackgroundColor)
                            .frame(width: scrollBarWidth, height: store.headerHeight)
                        
                        Divider()
                        
                        // Vertical ScrollBar synchronized with Gantt & LeftTree!
                        VerticalScrollBar(
                            offset: $store.scrollOffsetY,
                            maxOffset: maxOffsetY,
                            viewportHeight: canvasHeight,
                            totalHeight: totalContentHeight
                        )
                        .frame(width: scrollBarWidth, height: canvasHeight)
                        
                        // Bottom corner spacer where horizontal & vertical scrollbars meet
                        Color(NSColor.controlBackgroundColor)
                            .frame(width: scrollBarWidth, height: scrollBarHeight)
                    }
                    .frame(width: scrollBarWidth, height: visibleHeight)
                }
            }
            .frame(width: visibleWidth, height: visibleHeight)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
    }
}

// MARK: - Gantt Bars Layer (Row Virtualization)
/// 보이는 행(+앞뒤 여유 행)만 렌더링한다. 위/아래는 같은 높이의 빈 공간으로 채워 레이아웃은 기존과 동일하다.
/// 이 View는 세로 구간(yBucket)이 바뀔 때만 다시 계산되며, 픽셀 단위 스크롤은 ScrollOffsetView 가 처리한다.
struct GanttBarsLayer: View {
    @ObservedObject var store: ProjectStore
    let totalDays: Int
    let canvasAreaWidth: CGFloat
    let canvasHeight: CGFloat
    let totalCanvasWidth: CGFloat
    
    var body: some View {
        let rows = store.flattenedRows
        let rowHeight = store.rowHeight
        let window = store.scroll.rowWindow(viewportHeight: canvasHeight, rowHeight: rowHeight, totalRows: rows.count)
        let topOffset = CGFloat(window.lowerBound) * rowHeight
        
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows[window]) { row in
                GanttBarRowView(
                    store: store,
                    row: row,
                    totalDays: totalDays,
                    canvasAreaWidth: canvasAreaWidth
                )
                .frame(width: canvasAreaWidth, height: rowHeight, alignment: .leading)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(NSColor.separatorColor).opacity(0.25)),
                    alignment: .bottom
                )
            }
            
            // Bottom empty space to match LeftTreeView
            Spacer().frame(height: rowHeight + 20)
        }
        .frame(width: canvasAreaWidth, alignment: .topLeading)
        .offset(y: topOffset)
    }
}

// MARK: - Timeline Header View
struct TimelineHeaderView: View {
    @ObservedObject var store: ProjectStore
    var totalDays: Int
    var viewportWidth: CGFloat
    
    var body: some View {
        let dayWidth = store.dayWidth
        let window = store.scroll.dayWindow(viewportWidth: viewportWidth, dayWidth: dayWidth, totalDays: totalDays)
        let filterIndex = store.workloadFilterDayIndex
        let leftOffset = CGFloat(window.lowerBound) * dayWidth
        
        HStack(spacing: 0) {
            ForEach(store.timelineDays(window)) { day in
                let isFilterDate = day.index == filterIndex
                
                VStack(spacing: 2) {
                    if day.showsMonthLabel {
                        Text(day.monthLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    } else {
                        Text(day.shortLabel)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    
                    Text("\(day.dayNumber)")
                        .font(.system(size: 12, weight: (day.isToday || isFilterDate) ? .heavy : .semibold))
                        .foregroundColor(day.isToday ? .white : (isFilterDate ? Color.accentColor : (day.isWeekend ? .secondary : .primary)))
                        .frame(width: 22, height: 22)
                        .background(
                            day.isToday ? Circle().fill(Color.accentColor) : nil
                        )
                        .overlay(
                            isFilterDate && !day.isToday ?
                                Circle().strokeBorder(Color.accentColor, lineWidth: 2) : nil
                        )
                    
                    Text(day.weekdayLabel)
                        .font(.system(size: 9))
                        .foregroundColor(day.isWeekend ? .red.opacity(0.7) : (isFilterDate ? Color.accentColor : .secondary))
                }
                .frame(width: dayWidth, height: store.headerHeight)
                .background(
                    isFilterDate ?
                        Color.accentColor.opacity(0.12) :
                        (day.isWeekend ?
                            Color(NSColor.separatorColor).opacity(0.12) :
                            Color.clear)
                )
                .overlay(
                    Rectangle()
                        .frame(width: isFilterDate ? 2 : 1)
                        .foregroundColor(isFilterDate ? Color.accentColor.opacity(0.75) : Color(NSColor.separatorColor).opacity(0.3)),
                    alignment: .trailing
                )
            }
        }
        .offset(x: leftOffset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: store.headerHeight)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Timeline Grid Background
/// 보이는 날짜 구간만 Canvas 하나로 그린다. (날짜마다 View를 만들던 방식 대비 View 트리/비교 비용이 거의 없음)
struct TimelineGridView: View {
    @ObservedObject var store: ProjectStore
    var totalDays: Int
    var viewportWidth: CGFloat
    
    var body: some View {
        let dayWidth = store.dayWidth
        let window = store.scroll.dayWindow(viewportWidth: viewportWidth, dayWidth: dayWidth, totalDays: totalDays)
        let days = Array(store.timelineDays(window))
        let filterIndex = store.workloadFilterDayIndex
        let originX = CGFloat(window.lowerBound) * dayWidth
        
        Canvas { context, size in
            let accent = Color.accentColor
            let separator = Color(NSColor.separatorColor)
            for day in days {
                let x = CGFloat(day.index) * dayWidth - originX
                let isFilterDate = day.index == filterIndex
                
                let fillColor: Color? = isFilterDate ?
                    accent.opacity(0.10) :
                    (day.isToday ?
                        accent.opacity(0.06) :
                        (day.isWeekend ? separator.opacity(0.08) : nil))
                if let fillColor {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(fillColor)
                    )
                }
                
                // Trailing day separator line
                let lineWidth: CGFloat = isFilterDate ? 2 : 1
                let lineColor: Color = isFilterDate ?
                    accent.opacity(0.75) :
                    (day.isToday ? accent.opacity(0.4) : separator.opacity(0.25))
                context.fill(
                    Path(CGRect(x: x + dayWidth - lineWidth, y: 0, width: lineWidth, height: size.height)),
                    with: .color(lineColor)
                )
            }
        }
        .frame(width: CGFloat(window.count) * dayWidth)
        .offset(x: originX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Task Hover Tooltip Card
struct TaskTooltipCard: View {
    let task: TaskItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: task.colorHex))
                    .frame(width: 8, height: 8)
                Text(task.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                
                if task.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }
            
            Text("\(task.effectiveStartDate.formattedDateString) ~ \(task.effectiveEndDate.formattedDateString) (\(task.durationDays)일간)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                    .padding(.vertical, 1)
                
                Text(task.notes)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(minWidth: 160, maxWidth: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Gantt Bar Row
struct GanttBarRowView: View {
    @ObservedObject var store: ProjectStore
    let row: FlattenedTaskRow
    var totalDays: Int
    var canvasAreaWidth: CGFloat
    
    @State private var localDragOffset: CGFloat = 0
    @State private var localResizeLeft: CGFloat = 0
    @State private var localResizeRight: CGFloat = 0
    @State private var isDraggingBar: Bool = false
    @State private var isHoveringBar: Bool = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var lastClickTime: TimeInterval = 0
    @State private var hoverWorkItem: DispatchWorkItem? = nil
    
    var task: TaskItem { row.task }
    
    var body: some View {
        let dateRange = task.effectiveDateRange
        let startDays = store.timelineStartDate.daysBetween(dateRange.start)
        let totalDuration = max(1, dateRange.start.daysBetween(dateRange.end) + 1)
        
        let baseX = CGFloat(startDays) * store.dayWidth
        let baseWidth = CGFloat(totalDuration) * store.dayWidth
        
        let currentX = baseX + localDragOffset + localResizeLeft
        let currentWidth = max(store.dayWidth * 0.5, baseWidth + (localResizeRight - localResizeLeft))
        
        let titleApproxWidth = CGFloat(task.title.count) * 11.0 + 16.0
        let isTextInside = currentWidth >= titleApproxWidth
        let hasChildren = !task.children.isEmpty
        
        let isDimmed = store.isTaskDimmedByWorkloadFilter(task: task)
        
        // Coordinates relative to visible canvas viewport.
        // body 에서는 실시간 스크롤 값을 직접 읽어 내부에서 위치를 이동시킨다. (부모의 offset 대신)
        let barScreenLeft = currentX - store.scroll.x
        let barScreenRight = barScreenLeft + currentWidth
        let totalElementRight = isTextInside ? barScreenRight : (barScreenRight + titleApproxWidth)
        let isElementVisibleInCanvas = totalElementRight > 0 && barScreenLeft < canvasAreaWidth
        
        if task.isMilestone {
            milestoneDiamondView(baseX: baseX, canvasAreaWidth: canvasAreaWidth, titleApproxWidth: titleApproxWidth, isDimmed: isDimmed)
        } else {
            ZStack(alignment: .leading) {
                // Full row width container strictly leading-aligned from X=0
                Color.clear
                    .frame(width: canvasAreaWidth, height: store.rowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectedTaskId = task.id
                        store.clearWorkloadFilter()
                    }
                
                // The Task Bar
                ZStack(alignment: .leading) {
                    centerBarContent(isTextInside: isTextInside, hasChildren: hasChildren, barScreenLeft: barScreenLeft)
                        .frame(width: currentWidth, height: store.rowHeight - (hasChildren ? 10 : 12))
                        .background(barBackground(hasChildren: hasChildren))
                        .overlay(barBorder(hasChildren: hasChildren))
                    
                    if !hasChildren {
                        leftResizeHandle(currentWidth: currentWidth, barScreenLeft: barScreenLeft)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .zIndex(100)
                        
                        rightResizeHandle(currentWidth: currentWidth, barScreenRight: barScreenRight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .zIndex(100)
                    }
                }
                .frame(width: currentWidth, height: store.rowHeight - (hasChildren ? 10 : 12))
                .shadow(color: Color.black.opacity(isDimmed ? 0.03 : 0.12), radius: 2, x: 0, y: 1)
                .onContinuousHover { phase in
                    guard !isDraggingBar, localResizeLeft == 0, localResizeRight == 0 else {
                        hoverWorkItem?.cancel()
                        hoverWorkItem = nil
                        isHoveringBar = false
                        return
                    }
                    switch phase {
                    case .active(let loc):
                        // Calculate mouse position in visible canvas viewport coordinates (live scroll offset)
                        let mouseCanvasX = (currentX - store.scroll.x) + loc.x
                        // If mouse is outside visible canvas viewport (e.g. over LeftTreeView where mouseCanvasX < 0), immediately cancel hover!
                        guard mouseCanvasX >= 0 && mouseCanvasX <= canvasAreaWidth else {
                            hoverWorkItem?.cancel()
                            hoverWorkItem = nil
                            isHoveringBar = false
                            return
                        }
                        
                        hoverLocation = loc
                        // Consistently display tooltip after 0.5s on any bar
                        if !isHoveringBar && hoverWorkItem == nil {
                            let item = DispatchWorkItem {
                                isHoveringBar = true
                            }
                            hoverWorkItem = item
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
                        }
                    case .ended:
                        hoverWorkItem?.cancel()
                        hoverWorkItem = nil
                        isHoveringBar = false
                    }
                }
                .overlay(barOverlays(currentWidth: currentWidth, barScreenLeft: barScreenLeft), alignment: .topLeading)
                .offset(x: barScreenLeft, y: 0)
                .opacity(isDimmed ? 0.22 : 1.0)
                
                // Text outside bar if bar is too short
                if !isTextInside {
                    outsideTitleText(currentX: barScreenLeft, currentWidth: currentWidth, hasChildren: hasChildren, barScreenRight: barScreenRight)
                        .opacity(isDimmed ? 0.22 : 1.0)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDimmed)
            // "무조건 최 상단에 뜨도록 해" - 호버된 행 자체를 다른 모든 행보다 Z축 최상단으로 올림!
            .zIndex(isHoveringBar ? 9999 : 0)
            .allowsHitTesting(isElementVisibleInCanvas)
        }
    }
    
    // MARK: - Milestone Diamond Subview
    @ViewBuilder
    private func milestoneDiamondView(
        baseX: CGFloat,
        canvasAreaWidth: CGFloat,
        titleApproxWidth: CGFloat,
        isDimmed: Bool
    ) -> some View {
        let diamondSize: CGFloat = min(store.rowHeight - 14, 20)
        let diamondCenterX = baseX + (store.dayWidth / 2) + localDragOffset
        let diamondX = diamondCenterX - (diamondSize / 2)
        
        let screenLeft = diamondX - store.scroll.x
        let isVisible = screenLeft + diamondSize + titleApproxWidth > 0 && screenLeft < canvasAreaWidth
        
        ZStack(alignment: .leading) {
            // Full row container for background tap
            Color.clear
                .frame(width: canvasAreaWidth, height: store.rowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.selectedTaskId = task.id
                    store.clearWorkloadFilter()
                }
            
            // Diamond Shape
            ZStack {
                Diamond()
                    .fill(Color(hex: task.colorHex))
                    .frame(width: diamondSize, height: diamondSize)
                    .overlay(
                        Diamond()
                            .stroke(store.selectedTaskId == task.id ? Color.white : Color.black.opacity(0.25), lineWidth: store.selectedTaskId == task.id ? 2 : 1)
                    )
                
                if task.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: diamondSize, height: diamondSize)
            .shadow(color: Color.black.opacity(isDimmed ? 0.03 : 0.2), radius: 2, x: 0, y: 1)
            .cursor(.openHand)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(GanttCanvasSpace.name))
                    .onChanged { val in
                        hoverWorkItem?.cancel()
                        hoverWorkItem = nil
                        isHoveringBar = false
                        localDragOffset = val.translation.width
                    }
                    .onEnded { val in
                        let days = Int(round(localDragOffset / store.dayWidth))
                        localDragOffset = 0
                        if days != 0 {
                            let newStart = task.startDate.addingDays(days)
                            store.updateTaskDates(id: task.id, newStartDate: newStart, newEndDate: newStart)
                        }
                    }
            )
            .instantClick(
                onSingleClick: {
                    store.clearWorkloadFilter()
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    if isShift, let selectedId = store.selectedTaskId, selectedId != task.id {
                        store.handleBarShiftClick(fromTaskId: selectedId, toTaskId: task.id)
                    } else {
                        store.selectedTaskId = task.id
                    }
                },
                onDoubleClick: {
                    store.showDetail(for: task.id)
                    store.clearWorkloadFilter()
                }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    let mouseCanvasX = (diamondX - store.scroll.x) + loc.x
                    guard mouseCanvasX >= 0 && mouseCanvasX <= canvasAreaWidth else {
                        hoverWorkItem?.cancel()
                        hoverWorkItem = nil
                        isHoveringBar = false
                        return
                    }
                    hoverLocation = loc
                    if !isHoveringBar && hoverWorkItem == nil {
                        let item = DispatchWorkItem { isHoveringBar = true }
                        hoverWorkItem = item
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
                    }
                case .ended:
                    hoverWorkItem?.cancel()
                    hoverWorkItem = nil
                    isHoveringBar = false
                }
            }
            .overlay(
                Group {
                    if isHoveringBar {
                        let tipX = (screenLeft + diamondSize + 8 + 280 > canvasAreaWidth) ? (-280 - 8) : (diamondSize + 8)
                        TaskTooltipCard(task: task)
                            .offset(x: tipX, y: -20)
                            .allowsHitTesting(false)
                            .zIndex(10000)
                    }
                }
            )
            .offset(x: screenLeft, y: 0)
            .opacity(isDimmed ? 0.22 : 1.0)
            
            // Text outside diamond
            HStack(spacing: 4) {
                Text(task.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(task.isCompleted ? Color.gray : Color(hex: task.colorHex))
                    .strikethrough(task.isCompleted, color: Color.gray.opacity(0.7))
                    .lineLimit(1)
                
                let effectiveAssignees = store.project.assignees.filter { task.assigneeIds.contains($0.id) }
                if !effectiveAssignees.isEmpty {
                    Text("(\(effectiveAssignees.map { $0.name }.joined(separator: ", ")))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .offset(x: screenLeft + diamondSize + 6, y: 0)
            .opacity(isDimmed ? 0.22 : 1.0)
            .instantClick(
                onSingleClick: {
                    store.clearWorkloadFilter()
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    if isShift, let selectedId = store.selectedTaskId, selectedId != task.id {
                        store.handleBarShiftClick(fromTaskId: selectedId, toTaskId: task.id)
                    } else {
                        store.selectedTaskId = task.id
                    }
                },
                onDoubleClick: {
                    store.showDetail(for: task.id)
                    store.clearWorkloadFilter()
                }
            )
        }
        .animation(.easeInOut(duration: 0.2), value: isDimmed)
        .zIndex(isHoveringBar ? 9999 : 0)
        .allowsHitTesting(isVisible)
    }
    
    // MARK: - Subviews & Modifiers
    @ViewBuilder
    private func leftResizeHandle(currentWidth: CGFloat, barScreenLeft: CGFloat) -> some View {
        // Only render/enable resize handle if it is within the visible canvas viewport
        if task.children.isEmpty && barScreenLeft >= 0 {
            let handleW = min(max(currentWidth * 0.25, 14), 20)
            NativeResizeHandle(
                onDragging: { delta in
                    hoverWorkItem?.cancel()
                    hoverWorkItem = nil
                    isHoveringBar = false
                    localResizeLeft = delta
                },
                onEnded: { delta in
                    localResizeLeft = 0
                    let days = Int(round(delta / store.dayWidth))
                    if days != 0 {
                        let newStart = task.startDate.addingDays(days)
                        store.updateTaskDates(id: row.id, newStartDate: newStart, newEndDate: task.endDate)
                    }
                },
                onClick: { clickCount in
                    handleClickOrDoubleClick(clickCount: clickCount)
                }
            )
            .frame(width: handleW, height: store.rowHeight - 12)
        }
    }
    
    @ViewBuilder
    private func rightResizeHandle(currentWidth: CGFloat, barScreenRight: CGFloat) -> some View {
        // Only render/enable resize handle if it is within the visible canvas viewport
        if task.children.isEmpty && barScreenRight >= 0 && barScreenRight <= canvasAreaWidth + 20 {
            let handleW = min(max(currentWidth * 0.25, 14), 20)
            NativeResizeHandle(
                onDragging: { delta in
                    hoverWorkItem?.cancel()
                    hoverWorkItem = nil
                    isHoveringBar = false
                    localResizeRight = delta
                },
                onEnded: { delta in
                    localResizeRight = 0
                    let days = Int(round(delta / store.dayWidth))
                    if days != 0 {
                        let newEnd = task.endDate.addingDays(days)
                        store.updateTaskDates(id: row.id, newStartDate: task.startDate, newEndDate: newEnd)
                    }
                },
                onClick: { clickCount in
                    handleClickOrDoubleClick(clickCount: clickCount)
                }
            )
            .frame(width: handleW, height: store.rowHeight - 12)
        }
    }
    
    @ViewBuilder
    private func centerBarContent(isTextInside: Bool, hasChildren: Bool, barScreenLeft: CGFloat) -> some View {
        HStack(spacing: 4) {
            if hasChildren {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.9))
            }
            if task.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.9))
            }
            if isTextInside {
                Text(task.title)
                    .font(.system(size: 12, weight: hasChildren ? .bold : .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            // 고정된 캔버스 뷰포트 좌표계에서 측정: 움직이는 Bar 자신의 좌표계에 의한 이동량 흔들림이 없고,
            // startLocation.x 가 곧 뷰포트 내 X 좌표이므로 스크롤 오프셋을 더할 필요가 없다.
            DragGesture(minimumDistance: 0, coordinateSpace: .named(GanttCanvasSpace.name))
                .onChanged { value in
                    // Only respond if touch/click origin is within visible canvas viewport
                    let clickCanvasX = value.startLocation.x
                    guard clickCanvasX >= 0 && clickCanvasX <= canvasAreaWidth else { return }
                    
                    // Instant selection on the very first touch/click (0ms)!
                    if !isDraggingBar && abs(value.translation.width) <= 2 {
                        let isShift = NSEvent.modifierFlags.contains(.shift)
                        if !isShift && store.selectedTaskId != task.id {
                            store.selectedTaskId = task.id
                        }
                    }
                    
                    guard !hasChildren else { return }
                    if abs(value.translation.width) > 2 {
                        if !isDraggingBar {
                            isDraggingBar = true
                            hoverWorkItem?.cancel()
                            hoverWorkItem = nil
                            isHoveringBar = false
                        }
                        localDragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    let clickCanvasX = value.startLocation.x
                    guard clickCanvasX >= 0 && clickCanvasX <= canvasAreaWidth else { return }
                    
                    if isDraggingBar && abs(value.translation.width) > 2 {
                        isDraggingBar = false
                        localDragOffset = 0
                        let days = Int(round(value.translation.width / store.dayWidth))
                        if days != 0 {
                            store.shiftTaskBar(id: row.id, daysDelta: days)
                        }
                    } else {
                        isDraggingBar = false
                        localDragOffset = 0
                        handleClickOrDoubleClick()
                    }
                }
        )
    }
    
    private func handleDragEnded(translation: CGFloat) {
        if isDraggingBar && abs(translation) > 2 {
            isDraggingBar = false
            localDragOffset = 0
            let days = Int(round(translation / store.dayWidth))
            if days != 0 {
                store.shiftTaskBar(id: row.id, daysDelta: days)
            }
        } else {
            isDraggingBar = false
            localDragOffset = 0
            handleClickOrDoubleClick()
        }
    }
    
    private func handleClickOrDoubleClick(clickCount: Int? = nil) {
        store.clearWorkloadFilter()
        let count = clickCount ?? (NSApp.currentEvent?.clickCount ?? 1)
        let now = ProcessInfo.processInfo.systemUptime
        let doubleClickThreshold = max(0.2, min(0.35, NSEvent.doubleClickInterval))
        let isDoubleClickByTime = (now - lastClickTime < doubleClickThreshold) && lastClickTime > 0
        
        if count >= 2 || isDoubleClickByTime {
            lastClickTime = 0
            store.showDetail(for: task.id)
        } else {
            lastClickTime = now
            let isShift = NSEvent.modifierFlags.contains(.shift)
            if isShift, let selectedId = store.selectedTaskId, selectedId != task.id {
                store.handleBarShiftClick(fromTaskId: selectedId, toTaskId: task.id)
            } else {
                store.selectedTaskId = task.id
            }
        }
    }
    
    private func barBackground(hasChildren: Bool) -> some View {
        RoundedRectangle(cornerRadius: hasChildren ? 4 : 6)
            .fill(Color(hex: task.colorHex))
            .opacity(task.isCompleted ? 0.38 : (hasChildren ? 0.88 : 0.95))
    }
    
    private func barBorder(hasChildren: Bool) -> some View {
        RoundedRectangle(cornerRadius: hasChildren ? 4 : 6)
            .strokeBorder(
                store.selectedTaskId == task.id ? Color.white : (hasChildren ? Color.black.opacity(0.3) : Color.black.opacity(0.15)),
                lineWidth: store.selectedTaskId == task.id ? 2 : (hasChildren ? 1.5 : 1)
            )
    }
    
    @ViewBuilder
    private func barOverlays(currentWidth: CGFloat, barScreenLeft: CGFloat) -> some View {
        Group {
            if isHoveringBar && !isDraggingBar {
                let tooltipY = hoverLocation.y < 35 ? (hoverLocation.y + 24) : (hoverLocation.y - 55)
                let mouseCanvasX = barScreenLeft + hoverLocation.x
                let tooltipX: CGFloat = (mouseCanvasX + 280 + 16 > canvasAreaWidth)
                    ? max(-barScreenLeft + 8, hoverLocation.x - 280 - 12)
                    : (hoverLocation.x + 12)
                TaskTooltipCard(task: task)
                    .offset(x: tooltipX, y: tooltipY)
                    .allowsHitTesting(false)
                    .zIndex(99999)
            }
            
            if isDraggingBar {
                let deltaDays = Int(round(localDragOffset / store.dayWidth))
                Text(deltaDays > 0 ? "+\(deltaDays)일" : (deltaDays < 0 ? "\(deltaDays)일" : "0일"))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .offset(x: currentWidth / 2 - 16, y: -24)
                    .allowsHitTesting(false)
                    .zIndex(1000)
            }
        }
    }
    
    @ViewBuilder
    private func outsideTitleText(currentX: CGFloat, currentWidth: CGFloat, hasChildren: Bool, barScreenRight: CGFloat) -> some View {
        let isTextVisible = barScreenRight + 6 < canvasAreaWidth && barScreenRight + 120 > 0
        Text(task.title)
            .font(.system(size: 12, weight: hasChildren ? .bold : .semibold))
            .foregroundColor(task.isCompleted ? Color.gray : Color(hex: task.colorHex))
            .lineLimit(1)
            .padding(.leading, 6)
            .offset(x: currentX + currentWidth, y: 0)
            .allowsHitTesting(isTextVisible)
            .instantClick(
                onSingleClick: {
                    store.clearWorkloadFilter()
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    if isShift, let selectedId = store.selectedTaskId, selectedId != task.id {
                        store.handleBarShiftClick(fromTaskId: selectedId, toTaskId: task.id)
                    } else {
                        store.selectedTaskId = task.id
                    }
                },
                onDoubleClick: {
                    store.showDetail(for: task.id)
                    store.clearWorkloadFilter()
                }
            )
    }
}

// MARK: - Native macOS Resize Handle
struct NativeResizeHandle: NSViewRepresentable {
    var onDragging: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onClick: (Int) -> Void
    
    func makeNSView(context: Context) -> ResizeNSView {
        let view = ResizeNSView()
        view.onDragging = onDragging
        view.onEnded = onEnded
        view.onClick = onClick
        return view
    }
    
    func updateNSView(_ nsView: ResizeNSView, context: Context) {
        nsView.onDragging = onDragging
        nsView.onEnded = onEnded
        nsView.onClick = onClick
        // NOTE: 여기서 invalidateCursorRects 를 호출하지 않는다.
        // (모든 핸들의 모든 업데이트마다 호출되어 비용이 컸음)
        // 커서는 뷰를 자동으로 따라가는 .inVisibleRect 트래킹 영역에서 처리한다.
    }
    
    class ResizeNSView: NSView {
        var onDragging: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat) -> Void)?
        var onClick: ((Int) -> Void)?
        
        private var initialMouseX: CGFloat = 0
        private var isDragging = false
        
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            // .inVisibleRect: 뷰의 위치/크기가 바뀌어도 AppKit 이 영역을 자동으로 갱신한다.
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }
        
        override func cursorUpdate(with event: NSEvent) {
            NSCursor.resizeLeftRight.set()
        }
        
        override func mouseDown(with event: NSEvent) {
            initialMouseX = event.locationInWindow.x
            isDragging = false
            // Send exact clickCount from macOS (clickCount == 1 for single click, clickCount == 2 for double click)
            onClick?(event.clickCount)
        }
        
        override func mouseDragged(with event: NSEvent) {
            NSCursor.resizeLeftRight.set()
            let delta = event.locationInWindow.x - initialMouseX
            if abs(delta) > 1 {
                isDragging = true
            }
            if isDragging {
                onDragging?(delta)
            }
        }
        
        override func mouseUp(with event: NSEvent) {
            let delta = event.locationInWindow.x - initialMouseX
            if isDragging && abs(delta) > 1 {
                isDragging = false
                onEnded?(delta)
            } else {
                isDragging = false
                // Do NOT call onClick again on mouseUp! It was already processed on mouseDown.
            }
        }
    }
}

// MARK: - Cursor helper extension for macOS
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Dependency Arrows View
struct DependencyArrowsView: View {
    @ObservedObject var store: ProjectStore
    let canvasAreaWidth: CGFloat
    let canvasHeight: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let scrollX = store.scroll.x
            let scrollY = store.scroll.y
            context.translateBy(x: -scrollX, y: -scrollY)
            
            let flatRows = store.flattenedRows
            // 행 인덱스와 작업을 한 번에 조회할 수 있도록 사전 구성 (의존성마다 findTask 선형 탐색 제거)
            var rowLookup: [UUID: (index: Int, task: TaskItem)] = [:]
            rowLookup.reserveCapacity(flatRows.count)
            for (index, row) in flatRows.enumerated() {
                rowLookup[row.id] = (index, row.task)
            }
            
            for dep in store.project.dependencies {
                guard let fromEntry = rowLookup[dep.fromTaskId],
                      let toEntry = rowLookup[dep.toTaskId] else {
                    continue
                }
                let fromIndex = fromEntry.index
                let toIndex = toEntry.index
                let fromTask = fromEntry.task
                let toTask = toEntry.task
                
                let diamondHalfSize: CGFloat = 10.0
                
                let fromX: CGFloat
                if fromTask.isMilestone {
                    let fromStartDays = store.timelineStartDate.daysBetween(fromTask.startDate)
                    fromX = CGFloat(fromStartDays) * store.dayWidth + (store.dayWidth / 2) + diamondHalfSize
                } else {
                    let fromRange = fromTask.effectiveDateRange
                    let fromStartDays = store.timelineStartDate.daysBetween(fromRange.start)
                    let fromDuration = max(1, fromRange.start.daysBetween(fromRange.end) + 1)
                    fromX = CGFloat(fromStartDays + fromDuration) * store.dayWidth
                }
                let fromY = CGFloat(fromIndex) * store.rowHeight + (store.rowHeight / 2)
                
                let toX: CGFloat
                if toTask.isMilestone {
                    let toStartDays = store.timelineStartDate.daysBetween(toTask.startDate)
                    toX = CGFloat(toStartDays) * store.dayWidth + (store.dayWidth / 2) - diamondHalfSize
                } else {
                    let toRange = toTask.effectiveDateRange
                    let toStartDays = store.timelineStartDate.daysBetween(toRange.start)
                    toX = CGFloat(toStartDays) * store.dayWidth
                }
                let toY = CGFloat(toIndex) * store.rowHeight + (store.rowHeight / 2)
                
                var path = Path()
                path.move(to: CGPoint(x: fromX, y: fromY))
                
                let midX = fromX + (toX - fromX) / 2
                if toX >= fromX + 16 {
                    path.addCurve(
                        to: CGPoint(x: toX, y: toY),
                        control1: CGPoint(x: midX, y: fromY),
                        control2: CGPoint(x: midX, y: toY)
                    )
                } else {
                    let detourX = max(fromX, toX) + 24
                    path.addLine(to: CGPoint(x: fromX + 12, y: fromY))
                    path.addLine(to: CGPoint(x: detourX, y: fromY))
                    path.addLine(to: CGPoint(x: detourX, y: toY))
                    path.addLine(to: CGPoint(x: toX, y: toY))
                }
                
                let isFromDimmed = store.isTaskDimmedByWorkloadFilter(task: fromTask)
                let isToDimmed = store.isTaskDimmedByWorkloadFilter(task: toTask)
                let isArrowDimmed = isFromDimmed || isToDimmed
                
                context.stroke(
                    path,
                    with: .color(Color(hex: fromTask.colorHex).opacity(isArrowDimmed ? 0.15 : 0.85)),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                )
                
                var arrowPath = Path()
                arrowPath.move(to: CGPoint(x: toX, y: toY))
                arrowPath.addLine(to: CGPoint(x: toX - 7, y: toY - 4.5))
                arrowPath.addLine(to: CGPoint(x: toX - 7, y: toY + 4.5))
                arrowPath.closeSubpath()
                
                context.fill(arrowPath, with: .color(Color(hex: fromTask.colorHex).opacity(isArrowDimmed ? 0.15 : 1.0)))
            }
        }
        .allowsHitTesting(false)
    }
}

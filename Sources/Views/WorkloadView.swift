import SwiftUI
import AppKit

struct WorkloadView: View {
    @ObservedObject var store: ProjectStore
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Spacer()
                    Text("작업자별 워크로드 (가나다 순)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.accentColor)
                }
                .frame(width: store.leftPaneWidth, alignment: .trailing)
                .padding(.trailing, 16)
                
                Divider()
                
                Text("날짜별 참여 작업 수")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.leading, 12)
                
                Spacer()
                
                // Color Legend
                HStack(spacing: 12) {
                    LegendItem(color: Color(red: 0.52, green: 0.85, blue: 0.25), text: "1~2개")
                    LegendItem(color: Color(red: 0.23, green: 0.51, blue: 0.96), text: "3~4개")
                    LegendItem(color: Color(red: 0.94, green: 0.27, blue: 0.24), text: "5개 이상")
                }
                .padding(.trailing, 16)
            }
            .frame(height: 32)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Workload Content
            let assignees = store.sortedAssignees
            if assignees.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("등록된 작업자가 없습니다. 작업자 창에서 작업자를 추가하세요.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    // Left Column: Sorted Assignees (Width matches store.leftPaneWidth)
                    GeometryReader { leftGeo in
                        let viewportHeight = leftGeo.size.height
                        let rowHeight: CGFloat = 35.0
                        let totalContentHeight = CGFloat(assignees.count) * rowHeight
                        let maxOffsetY = max(0, totalContentHeight - viewportHeight)
                        
                        ZStack(alignment: .topTrailing) {
                            ScrollOffsetView(scroll: store.scroll, horizontal: false, vertical: .workload) {
                                VStack(spacing: 0) {
                                    ForEach(assignees) { assignee in
                                        HStack(spacing: 8) {
                                            Spacer()
                                            
                                            Text(assignee.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            
                                            if let img = assignee.avatarImage {
                                                Image(nsImage: img)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 24, height: 24)
                                                    .clipShape(Circle())
                                            } else {
                                                Image(systemName: "person.circle.fill")
                                                    .resizable()
                                                    .frame(width: 24, height: 24)
                                                    .foregroundColor(.blue.opacity(0.8))
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .frame(width: store.leftPaneWidth, height: 34)
                                        .background(Color(NSColor.windowBackgroundColor))
                                        Divider()
                                    }
                                }
                            }
                            
                            // Scroll wheel capture for left column
                            PanAndScrollOverlay(
                                onScroll: { _, dy in
                                    store.workloadScrollOffsetY = min(maxOffsetY, max(0, store.workloadScrollOffsetY - dy))
                                },
                                onRightPan: { _, _ in }
                            )
                        }
                        .frame(width: store.leftPaneWidth, height: viewportHeight, alignment: .topTrailing)
                        .clipped()
                    }
                    .frame(width: store.leftPaneWidth)
                    
                    Divider()
                    
                    // Right Column: Timeline Grid with Count Badges (Horizontal scroll locked with Gantt, Vertical scrollbar enabled)
                    GeometryReader { rightGeo in
                        let visibleWidth = rightGeo.size.width
                        let rowHeight: CGFloat = 35.0
                        let totalContentHeight = CGFloat(assignees.count) * rowHeight
                        let viewportHeight = rightGeo.size.height
                        let maxOffsetY = max(0, totalContentHeight - viewportHeight)
                        let scrollBarWidth: CGFloat = maxOffsetY > 0 ? 14 : 0
                        let gridAreaWidth = max(50, visibleWidth - scrollBarWidth)
                        
                        // 실시간 오프셋 대신 "현재 가로 구간의 상한값" 사용 (구간이 바뀔 때만 재계산)
                        let daysNeeded = Int(ceil((gridAreaWidth + store.scroll.xBucketUpperBound) / store.dayWidth)) + 30
                        let daysToRender = max(store.timelineTotalDays, daysNeeded)
                        let totalCanvasWidth = max(CGFloat(daysToRender) * store.dayWidth, gridAreaWidth + 1200)
                        let maxOffsetX = max(0, totalCanvasWidth - gridAreaWidth)
                        
                        HStack(spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                ScrollOffsetView(scroll: store.scroll, horizontal: true, vertical: .workload) {
                                    WorkloadGridLayer(
                                        store: store,
                                        assignees: assignees,
                                        totalDays: daysToRender,
                                        viewportWidth: gridAreaWidth,
                                        totalCanvasWidth: totalCanvasWidth
                                    )
                                }
                                
                                // Scroll wheel overlay to allow panning timeline and scrolling workload vertically
                                PanAndScrollOverlay(
                                    onScroll: { dx, dy in
                                        store.scrollOffsetX = min(maxOffsetX, max(0, store.scrollOffsetX - dx))
                                        store.workloadScrollOffsetY = min(maxOffsetY, max(0, store.workloadScrollOffsetY - dy))
                                    },
                                    onRightPan: { dx, dy in
                                        store.panScrollWorkload(
                                            deltaX: dx,
                                            deltaY: dy,
                                            maxOffsetX: maxOffsetX,
                                            maxOffsetY: maxOffsetY
                                        )
                                    }
                                )
                            }
                            .frame(width: gridAreaWidth, height: viewportHeight, alignment: .topLeading)
                            .clipped()
                            
                            // Vertical ScrollBar for Workload!
                            if maxOffsetY > 0 {
                                VerticalScrollBar(
                                    offset: $store.workloadScrollOffsetY,
                                    maxOffset: maxOffsetY,
                                    viewportHeight: viewportHeight,
                                    totalHeight: totalContentHeight
                                )
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Workload Grid Layer (Day Virtualization)
/// 보이는 날짜 구간(+앞뒤 여유)만 셀을 만든다. 가로 구간(xBucket)이 바뀔 때만 다시 계산되며,
/// 픽셀 단위 스크롤은 바깥의 ScrollOffsetView 가 처리한다.
struct WorkloadGridLayer: View {
    @ObservedObject var store: ProjectStore
    let assignees: [Assignee]
    let totalDays: Int
    let viewportWidth: CGFloat
    let totalCanvasWidth: CGFloat
    
    var body: some View {
        let dayWidth = store.dayWidth
        let window = store.scroll.dayWindow(viewportWidth: viewportWidth, dayWidth: dayWidth, totalDays: totalDays)
        let days = store.timelineDays(window)
        let filterAssigneeId = store.selectedWorkloadFilter?.assigneeId
        let filterDayIndex = store.workloadFilterDayIndex
        let leftOffset = CGFloat(window.lowerBound) * dayWidth
        
        VStack(spacing: 0) {
            ForEach(assignees) { assignee in
                HStack(spacing: 0) {
                    ForEach(days) { day in
                        let count = store.activeTaskCount(for: assignee.id, dayIndex: day.index)
                        let isSelected = filterAssigneeId == assignee.id && filterDayIndex == day.index
                        
                        WorkloadCell(
                            count: count,
                            isToday: day.isToday,
                            isWeekend: day.isWeekend,
                            isSelected: isSelected
                        )
                        .frame(width: dayWidth, height: 34)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.toggleWorkloadFilter(assigneeId: assignee.id, date: day.date)
                        }
                        .overlay(
                            Rectangle()
                                .frame(width: 1)
                                .foregroundColor(Color(NSColor.separatorColor).opacity(0.2)),
                            alignment: .trailing
                        )
                    }
                }
                .frame(height: 34)
                .offset(x: leftOffset)
                
                Divider()
            }
        }
    }
}

struct LegendItem: View {
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

struct WorkloadCell: View {
    let count: Int
    let isToday: Bool
    let isWeekend: Bool
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            if isToday {
                Color.accentColor.opacity(0.06)
            } else if isWeekend {
                Color(NSColor.separatorColor).opacity(0.08)
            } else {
                Color.clear
            }
            
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.18))
            }
            
            if count > 0 {
                // Single digit display (0-9)
                let badgeText = count > 9 ? "9+" : "\(count)"
                Text(badgeText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(badgeColor(for: count))
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
            }
            
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
    }
    
    /// "만약 1-2면 연두색, 3-4면 파란색, 5이상이면 빨간색으로 표시."
    private func badgeColor(for count: Int) -> Color {
        switch count {
        case 1...2:
            return Color(red: 0.52, green: 0.85, blue: 0.25) // 연두색 (Lime Green)
        case 3...4:
            return Color(red: 0.23, green: 0.51, blue: 0.96) // 파란색 (Blue)
        default:
            return Color(red: 0.94, green: 0.27, blue: 0.24) // 빨간색 (Red)
        }
    }
}

import SwiftUI
import AppKit

struct UnfinishedMilestonesView: View {
    @ObservedObject var store: ProjectStore
    var onClose: (() -> Void)? = nil
    
    // Uncompleted milestones sorted by start date
    var uncompletedMilestones: [TaskItem] {
        let all = store.getAllTasksFlat()
        return all.filter { $0.isMilestone && !$0.isCompleted }
            .sorted { $0.startDate < $1.startDate }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Window Header
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘 기준 미완료 마일스톤")
                        .font(.system(size: 15, weight: .bold))
                    Text("더블클릭하여 세부 설정을 열고 수정할 수 있습니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(uncompletedMilestones.count)개 남음")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Milestones List
            if uncompletedMilestones.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green.opacity(0.8))
                    Text("미완료된 마일스톤이 없습니다.")
                        .font(.system(size: 14, weight: .semibold))
                    Text("모든 마일스톤 작업이 성공적으로 완료되었습니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(uncompletedMilestones) { milestone in
                            MilestoneRowView(
                                milestone: milestone,
                                store: store,
                                onDoubleClick: {
                                    // Open TaskDetailSheet with milestone conversion disabled
                                    TaskDetailWindowManager.shared.show(
                                        taskId: milestone.id,
                                        store: store,
                                        isConvertMilestoneDisabled: true
                                    )
                                }
                            )
                        }
                    }
                    .padding(10)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("※ 마일스톤 세부 설정 창에서 마일스톤을 일반 작업으로 변환할 수 없습니다.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("닫기") {
                    if let onClose = onClose {
                        onClose()
                    }
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 460, idealWidth: 580, maxWidth: 720, minHeight: 360, idealHeight: 570)
    }
}

// MARK: - Milestone Row View
struct MilestoneRowView: View {
    let milestone: TaskItem
    @ObservedObject var store: ProjectStore
    var onDoubleClick: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        let today = Date().startOfDay
        let daysDiff = today.daysBetween(milestone.startDate.startOfDay)
        
        let assignedList = store.project.assignees.filter { milestone.assigneeIds.contains($0.id) }
        let ancestors = store.getAncestorTasks(for: milestone.id)
        
        HStack(spacing: 12) {
            // Milestone Diamond Icon
            ZStack {
                Diamond()
                    .fill(Color(hex: milestone.colorHex))
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
            }
            .frame(width: 24, height: 24)
            
            // Title & Date info
            VStack(alignment: .leading, spacing: 3) {
                // Ancestor / Parent Task Breadcrumb
                if !ancestors.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        ForEach(Array(ancestors.enumerated()), id: \.offset) { idx, parent in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            Text(parent.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                HStack(spacing: 6) {
                    Text(milestone.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: milestone.colorHex))
                        .lineLimit(1)
                    
                    // D-day Badge
                    if daysDiff == 0 {
                        Text("D-Day (오늘)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    } else if daysDiff > 0 {
                        Text("D-\(daysDiff)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    } else {
                        Text("\(abs(daysDiff))일 지남")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(milestone.startDate.formattedDateString)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Assignees
            if !assignedList.isEmpty {
                HStack(spacing: 6) {
                    ForEach(assignedList) { a in
                        HStack(spacing: 4) {
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
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.separatorColor).opacity(0.2))
                        .cornerRadius(4)
                    }
                }
            } else {
                Text("담당자 없음")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { h in
            isHovering = h
        }
        .instantClick(
            onSingleClick: {
                store.selectedTaskId = milestone.id
            },
            onDoubleClick: {
                onDoubleClick()
            }
        )
        .help("더블클릭하여 세부 설정 열기")
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TaskDetailSheet: View {
    @ObservedObject var store: ProjectStore
    let taskId: UUID
    var isConvertMilestoneDisabled: Bool = false
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    // Editable state
    @State private var title: String = ""
    @State private var selectedColorHex: String = Palette.defaultColor
    @State private var startDateText: String = ""
    @State private var endDateText: String = ""
    @State private var startDateValue: Date = Date()
    @State private var endDateValue: Date = Date()
    @State private var isCompleted: Bool = false
    @State private var isMilestone: Bool = false
    @State private var notes: String = ""
    @State private var showStartDatePicker: Bool = false
    @State private var showEndDatePicker: Bool = false
    @State private var showColorPicker: Bool = false
    @State private var showAssigneePopover: Bool = false
    @State private var assigneeIds: [UUID] = []
    @State private var showAssigneeManager: Bool = false
    
    // Attachment state
    @State private var selectedAttachmentId: UUID? = nil
    @State private var keyMonitor: Any? = nil
    
    @State private var originalTasksSnapshot: [TaskItem] = []
    @State private var originalDependenciesSnapshot: [Dependency] = []
    @State private var originalIsDirtySnapshot: Bool = false
    @State private var notesDebounceWorkItem: DispatchWorkItem? = nil
    @State private var titleDebounceWorkItem: DispatchWorkItem? = nil
    @State private var isReverting: Bool = false
    
    var task: TaskItem? {
        store.findTask(id: taskId)
    }
    
    var hasChildren: Bool {
        !(task?.children.isEmpty ?? true)
    }
    
    var effectiveAssigneeIds: Set<UUID> {
        if let t = task, !t.children.isEmpty {
            return Set(store.effectiveAssigneeIds(for: t))
        }
        return Set(assigneeIds)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Modal Header (상단 타이틀 바)
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    if isMilestone {
                        Diamond()
                            .fill(Color(hex: selectedColorHex))
                            .frame(width: 14, height: 14)
                    } else {
                        Circle()
                            .fill(Color(hex: selectedColorHex))
                            .frame(width: 14, height: 14)
                    }
                    
                    Text(isMilestone ? "마일스톤 세부 설정" : "작업 세부 설정")
                        .font(.system(size: 15, weight: .bold))
                    
                    if isMilestone {
                        Text("마일스톤")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }
                
                // 마일스톤으로 전환하기 / 일반작업으로 전환하기 버튼
                Button(action: {
                    toggleMilestone()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isMilestone ? "arrow.triangle.2.circlepath" : "rhombus.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isMilestone ? .secondary : .red)
                        Text(isMilestone ? "일반작업으로 전환하기" : "마일스톤으로 전환하기")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isConvertMilestoneDisabled)
                .help(isConvertMilestoneDisabled ? "미완료 마일스톤 목록에서 열린 창에서는 일반 작업으로 전환할 수 없습니다." : (isMilestone ? "일반 작업으로 전환" : "마일스톤으로 전환 (기간 1일)"))
                
                // 작업 완료하기 / 작업 완료됨 버튼
                Button(action: {
                    if let t = task {
                        store.toggleTaskCompletion(id: t.id)
                        if let updated = store.findTask(id: t.id) {
                            self.isCompleted = updated.isCompleted
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                        Text(isCompleted ? "작업 완료됨" : "작업 완료하기")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(isCompleted ? .green : .accentColor)
                .help(isCompleted ? "클릭하여 미완료 상태로 전환" : "클릭하여 작업 완료 처리")
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content Body - Left 4 sections : Right Attachments sidebar
            HStack(spacing: 0) {
                // Left 4 Sections Area
                VStack(alignment: .leading, spacing: 14) {
                    
                    // ==========================================
                    // 창 1단: 작업이름 (편집 가능) + 색상 아이콘 (하위 일괄 적용)
                    // ==========================================
                    VStack(alignment: .leading, spacing: 6) {
                        Text("작업 이름 및 테마 색상")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            TextField("작업 이름 입력", text: $title)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 14, weight: .medium))
                                .onSubmit {
                                    saveAndClose()
                                }
                                .onChange(of: title) { _, newVal in
                                    TaskDetailWindowManager.shared.updateTitle(newVal, isMilestone: isMilestone)
                                    titleDebounceWorkItem?.cancel()
                                    let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    let work = DispatchWorkItem {
                                        guard !isReverting else { return }
                                        if var t = store.findTask(id: taskId), t.title != trimmed {
                                            t.title = trimmed
                                            store.updateTask(t)
                                        }
                                    }
                                    titleDebounceWorkItem = work
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
                                }
                            
                            // Color Picker Icon
                            Button(action: {
                                showColorPicker.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: selectedColorHex))
                                        .frame(width: 18, height: 18)
                                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                                    Image(systemName: "paintpalette.fill")
                                        .font(.system(size: 12))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showColorPicker) {
                                ColorPickerPaletteView(selectedHex: $selectedColorHex) { newHex in
                                    selectedColorHex = newHex
                                    store.setTaskColorRecursively(id: taskId, hex: newHex)
                                    showColorPicker = false
                                }
                                .padding(12)
                            }
                            .help("색상 변경 (트리 하위 작업까지 일괄 적용)")
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    
                    // ==========================================
                    // 작업자 배정 (1단 바로 아래)
                    // ==========================================
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("작업자 배정")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            if hasChildren {
                                Spacer()
                                Text("하위 작업 자동 합산")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                            }
                        }
                        
                        let assignedList = store.project.assignees.filter { effectiveAssigneeIds.contains($0.id) }
                        
                        HStack(spacing: 8) {
                            // "작업자 설정" 버튼 (가장 왼쪽에 배치)
                            Button(action: {
                                if hasChildren {
                                    let alert = NSAlert()
                                    alert.messageText = "작업자 직접 선택 불가"
                                    alert.informativeText = "하위 작업이 있는 작업은 작업자를 직접 선택할 수 없습니다.\n하위 작업에 참여 중인 작업자들이 자동으로 합산되어 표시됩니다."
                                    alert.alertStyle = .informational
                                    alert.addButton(withTitle: "확인")
                                    alert.runModal()
                                } else {
                                    showAssigneePopover.toggle()
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                    Text("작업자 설정")
                                        .font(.system(size: 12, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help(hasChildren ? "하위 작업 자동 합산 (직접 변경 불가)" : "작업자 선택 및 배정 목록 열기")
                            .popover(isPresented: $showAssigneePopover) {
                                AssigneePickerPopover(
                                    store: store,
                                    assigneeIds: $assigneeIds,
                                    onToggle: { id in
                                        toggleAssignee(id)
                                    },
                                    onManage: {
                                        showAssigneePopover = false
                                        showAssigneeManager = true
                                    }
                                )
                            }
                            
                            // 선택된 작업자만 가로로 표시
                            if assignedList.isEmpty {
                                Text("배정된 작업자 없음")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .padding(.leading, 4)
                            } else {
                                HStack(spacing: 6) {
                                    ForEach(assignedList) { a in
                                        HStack(spacing: 5) {
                                            if let img = a.avatarImage {
                                                Image(nsImage: img)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 20, height: 20)
                                                    .clipShape(Circle())
                                            } else {
                                                Image(systemName: "person.circle.fill")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 20, height: 20)
                                                    .foregroundColor(.blue.opacity(0.85))
                                            }
                                            
                                            Text(a.name)
                                                .font(.system(size: 12, weight: .medium))
                                            
                                            if !hasChildren {
                                                Button(action: {
                                                    toggleAssignee(a.id)
                                                }) {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundColor(.secondary.opacity(0.65))
                                                }
                                                .buttonStyle(.plain)
                                                .help("\(a.name) 배정 해제")
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    
                    // ==========================================
                    // 창 2단: 작업 기간 (시작 날짜 - 끝 날짜, 캘린더 아이콘, 직접 수정)
                    // ==========================================
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("작업 기간 설정 (끝 날짜는 시작 날짜보다 항상 미래여야 함)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            if hasChildren {
                                Spacer()
                                Text("하위 작업 기간 자동 동기화")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .cornerRadius(4)
                            } else if isMilestone {
                                Spacer()
                                Text("마일스톤 (1일 고정)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.12))
                                    .cornerRadius(4)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            // Start Date Box
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .foregroundColor(hasChildren ? .secondary : .accentColor)
                                TextField("YYYY-MM-DD", text: $startDateText)
                                    .textFieldStyle(.plain)
                                    .frame(width: 90)
                                    .onSubmit {
                                        applyStartDateText()
                                    }
                                
                                Button(action: {
                                    showStartDatePicker.toggle()
                                }) {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showStartDatePicker) {
                                    DatePicker("", selection: $startDateValue, displayedComponents: [.date])
                                        .datePickerStyle(.graphical)
                                        .padding(8)
                                        .onChange(of: startDateValue) { _, newDate in
                                            onStartDatePicked(newDate)
                                            showStartDatePicker = false
                                        }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(hasChildren ? Color(NSColor.controlBackgroundColor) : Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                            .disabled(hasChildren)
                            
                            Text("~")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            // End Date Box (Disabled if milestone or has children)
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .foregroundColor((hasChildren || isMilestone) ? .secondary : .accentColor)
                                TextField("YYYY-MM-DD", text: $endDateText)
                                    .textFieldStyle(.plain)
                                    .frame(width: 90)
                                    .onSubmit {
                                        applyEndDateText()
                                    }
                                
                                Button(action: {
                                    showEndDatePicker.toggle()
                                }) {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(isMilestone)
                                .popover(isPresented: $showEndDatePicker) {
                                    DatePicker("", selection: $endDateValue, displayedComponents: [.date])
                                        .datePickerStyle(.graphical)
                                        .padding(8)
                                        .onChange(of: endDateValue) { _, newDate in
                                            onEndDatePicked(newDate)
                                            showEndDatePicker = false
                                        }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((hasChildren || isMilestone) ? Color(NSColor.controlBackgroundColor) : Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                            .disabled(hasChildren || isMilestone)
                            
                            // Total duration badge
                            if isMilestone {
                                Text("1일간 (마일스톤)")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.12))
                                    .foregroundColor(.red)
                                    .cornerRadius(4)
                            } else if let t = task {
                                Text("\(t.durationDays)일간")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                            }
                        }
                        
                        // 날짜 선택 버튼들 아랫 줄: 기간 조정 관련 텍스트와 버튼
                        HStack(spacing: 8) {
                            Text("기간 조정:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                store.adjustTaskDuration(id: taskId, byDays: -1)
                                refreshDatesFromStore()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "minus")
                                    Text("1일 단축")
                                }
                                .frame(height: 22)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(hasChildren || isMilestone)
                            
                            Button(action: {
                                store.adjustTaskDuration(id: taskId, byDays: 1)
                                refreshDatesFromStore()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                    Text("1일 연장")
                                }
                                .frame(height: 22)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(hasChildren || isMilestone)
                            
                            Spacer()
                        }
                        .padding(.top, 2)
                        
                        if isConvertMilestoneDisabled {
                            Text("※ 미완료 마일스톤 창을 통해 열린 작업은 일반 작업으로 전환할 수 없습니다.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else if hasChildren {
                            Text("※ 하위 작업이 있는 작업의 기간은 모든 하위 작업의 첫 시작부터 가장 늦은 종료 시점으로 자동 결정되므로 직접 수정할 수 없습니다.")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        } else if isMilestone {
                            Text("※ 마일스톤 작업은 기간이 1일로 고정되며 시작일과 종료일이 동일하게 자동 유지됩니다.")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        } else {
                            Text("※ 기간을 조정하면 이 작업과 연결된 후속 작업(Dependencies)의 일정이 함께 연동됩니다.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    
                    // ==========================================
                    // 창 4단: 상세 설명
                    // ==========================================
                    VStack(alignment: .leading, spacing: 6) {
                        Text("상세 설명")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $notes)
                                .font(.system(size: 13))
                                .lineSpacing(4)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .padding(6)
                                .onChange(of: notes) { _, newNotes in
                                    notesDebounceWorkItem?.cancel()
                                    let work = DispatchWorkItem {
                                        guard !isReverting else { return }
                                        if var t = store.findTask(id: taskId), t.notes != newNotes {
                                            t.notes = newNotes
                                            store.updateTask(t)
                                        }
                                    }
                                    notesDebounceWorkItem = work
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
                                }
                            
                            if notes.isEmpty {
                                Text("작업에 대한 상세 설명 및 메모를 입력하세요...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                // Right Side: Attachment Box
                AttachmentSidebarView(
                    store: store,
                    taskId: taskId,
                    selectedAttachmentId: $selectedAttachmentId
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Bottom Action ("취소" 및 "완료" 버튼)
            HStack(spacing: 12) {
                Spacer()
                
                Button("취소") {
                    cancelAndRevert()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("완료") {
                    saveAndClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 780, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .sheet(isPresented: $showAssigneeManager) {
            AssigneeManagerSheet(store: store, taskId: taskId)
        }
        .onChange(of: store.findTask(id: taskId)?.assigneeIds) { _, newIds in
            if let ids = newIds {
                self.assigneeIds = ids
            }
        }
        .onAppear {
            loadFromTask()
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
            titleDebounceWorkItem?.cancel()
            notesDebounceWorkItem?.cancel()
            if !isReverting {
                saveCurrentStateToStore()
            }
        }
    }
    
    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle Del key (backspace 51, delete 117)
            if event.keyCode == 51 || event.keyCode == 117 {
                // If text editor is focused, let text editing handle it
                if let window = NSApp.keyWindow,
                   let responder = window.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }
                
                if let attId = selectedAttachmentId {
                    store.removeAttachment(attachmentId: attId, fromTaskId: taskId)
                    selectedAttachmentId = nil
                    return nil // Handled
                }
            }
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
    
    private func loadFromTask() {
        guard let t = store.findTask(id: taskId) else { return }
        self.originalTasksSnapshot = store.project.tasks
        self.originalDependenciesSnapshot = store.project.dependencies
        self.originalIsDirtySnapshot = store.isDirty
        
        self.title = t.title
        self.selectedColorHex = t.colorHex
        self.startDateValue = t.startDate
        self.endDateValue = t.isMilestone ? t.startDate : t.endDate
        self.startDateText = t.startDate.formattedDateString
        self.endDateText = (t.isMilestone ? t.startDate : t.endDate).formattedDateString
        self.isCompleted = t.isCompleted
        self.isMilestone = t.isMilestone
        self.notes = t.notes
        self.assigneeIds = t.assigneeIds
    }
    
    private func toggleAssignee(_ id: UUID) {
        if assigneeIds.contains(id) {
            assigneeIds.removeAll { $0 == id }
        } else {
            assigneeIds.append(id)
        }
        if var t = store.findTask(id: taskId) {
            t.assigneeIds = assigneeIds
            store.updateTask(t)
        }
    }
    
    private func cancelAndRevert() {
        isReverting = true
        titleDebounceWorkItem?.cancel()
        notesDebounceWorkItem?.cancel()
        if !originalTasksSnapshot.isEmpty {
            store.project.tasks = originalTasksSnapshot
            store.project.dependencies = originalDependenciesSnapshot
            store.isDirty = originalIsDirtySnapshot
            store.syncHierarchy()
            store.invalidateCache()
        }
        store.detailTask = nil
        if let onClose = onClose {
            onClose()
        } else {
            dismiss()
        }
    }
    
    private func refreshDatesFromStore() {
        guard let t = store.findTask(id: taskId) else { return }
        self.startDateValue = t.startDate
        self.endDateValue = t.isMilestone ? t.startDate : t.endDate
        self.startDateText = t.startDate.formattedDateString
        self.endDateText = (t.isMilestone ? t.startDate : t.endDate).formattedDateString
    }
    
    private func onStartDatePicked(_ date: Date) {
        let cleanStart = date.startOfDay
        self.startDateText = cleanStart.formattedDateString
        self.startDateValue = cleanStart
        
        if isMilestone {
            self.endDateValue = cleanStart
            self.endDateText = cleanStart.formattedDateString
            store.updateTaskDates(id: taskId, newStartDate: cleanStart, newEndDate: cleanStart)
            return
        }
        
        var validEnd = endDateValue
        if validEnd < cleanStart {
            validEnd = cleanStart.addingDays(1)
            self.endDateValue = validEnd
            self.endDateText = validEnd.formattedDateString
        }
        store.updateTaskDates(id: taskId, newStartDate: cleanStart, newEndDate: validEnd)
    }
    
    private func onEndDatePicked(_ date: Date) {
        guard !isMilestone else { return }
        let cleanEnd = date.startOfDay
        let cleanStart = startDateValue.startOfDay
        let validEnd = max(cleanStart, cleanEnd)
        self.endDateValue = validEnd
        self.endDateText = validEnd.formattedDateString
        store.updateTaskDates(id: taskId, newStartDate: cleanStart, newEndDate: validEnd)
    }
    
    private func applyStartDateText() {
        if let parsed = Date.parse(string: startDateText) {
            onStartDatePicked(parsed)
        } else {
            startDateText = startDateValue.formattedDateString
        }
    }
    
    private func applyEndDateText() {
        guard !isMilestone else {
            endDateText = startDateValue.formattedDateString
            return
        }
        if let parsed = Date.parse(string: endDateText) {
            onEndDatePicked(parsed)
        } else {
            endDateText = endDateValue.formattedDateString
        }
    }
    
    private func toggleMilestone() {
        if !isMilestone {
            // Trying to convert to milestone
            // "마일스톤은 하위 작업을 가질 수 없음. 만약 하위 작업이 있는 작업을 마일스톤으로 바꾸고자 하면 에러 메세지를 띄우면 됨."
            if let t = task, !t.children.isEmpty {
                let alert = NSAlert()
                alert.messageText = "마일스톤 전환 불가"
                alert.informativeText = "하위 작업이 있는 작업은 마일스톤으로 전환할 수 없습니다."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "확인")
                alert.runModal()
                return
            }
            
            isMilestone = true
            endDateValue = startDateValue
            endDateText = startDateText
            store.setTaskMilestone(id: taskId, isMilestone: true)
            store.updateTaskDates(id: taskId, newStartDate: startDateValue, newEndDate: startDateValue)
            TaskDetailWindowManager.shared.updateTitle(title, isMilestone: true)
        } else {
            // Convert to normal task
            isMilestone = false
            store.setTaskMilestone(id: taskId, isMilestone: false)
            TaskDetailWindowManager.shared.updateTitle(title, isMilestone: false)
        }
    }
    
    private func saveAndClose() {
        titleDebounceWorkItem?.cancel()
        notesDebounceWorkItem?.cancel()
        if var t = store.findTask(id: taskId) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let orig = originalTasksSnapshot.first(where: { $0.id == taskId })
            let titleChanged = !trimmed.isEmpty && trimmed != (orig?.title ?? t.title)
            let notesChanged = notes != (orig?.notes ?? t.notes)
            let completedChanged = isCompleted != (orig?.isCompleted ?? t.isCompleted)
            let milestoneChanged = isMilestone != (orig?.isMilestone ?? t.isMilestone)
            let assigneesChanged = assigneeIds != (orig?.assigneeIds ?? t.assigneeIds)
            
            if titleChanged || notesChanged || completedChanged || milestoneChanged || assigneesChanged {
                store.recordUndo()
            }
            if !trimmed.isEmpty { t.title = trimmed }
            t.notes = notes
            t.isCompleted = isCompleted
            t.isMilestone = isMilestone
            t.assigneeIds = assigneeIds
            if isMilestone {
                t.endDate = t.startDate
            }
            store.updateTask(t)
        }
        store.detailTask = nil
        if let onClose = onClose {
            onClose()
        } else {
            dismiss()
        }
    }
    
    private func saveCurrentStateToStore() {
        guard !isReverting else { return }
        if var t = store.findTask(id: taskId) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { t.title = trimmed }
            t.notes = notes
            t.isCompleted = isCompleted
            t.isMilestone = isMilestone
            t.assigneeIds = assigneeIds
            if isMilestone {
                t.endDate = t.startDate
            }
            store.updateTask(t)
        }
    }
}

// MARK: - Attachment Sidebar View
struct AttachmentSidebarView: View {
    @ObservedObject var store: ProjectStore
    let taskId: UUID
    @Binding var selectedAttachmentId: UUID?
    
    var task: TaskItem? {
        store.findTask(id: taskId)
    }
    
    var attachments: [TaskAttachment] {
        task?.attachments ?? []
    }
    
    @State private var isTargeted: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("첨부 파일")
                    .font(.system(size: 12, weight: .bold))
                
                Spacer()
                
                Text("\(attachments.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.separatorColor).opacity(0.3))
                    .cornerRadius(4)
            }
            .padding(.bottom, 2)
            
            // Drop Box & List
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [4, 4] : [])
                    )
                
                if attachments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 26))
                            .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
                        
                        Text("파일을 여기에\n드래그하여 첨부")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("Attachments 폴더에\n자동 복사 및 연결")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(attachments) { att in
                                AttachmentItemRow(
                                    attachment: att,
                                    isSelected: selectedAttachmentId == att.id,
                                    onSelect: {
                                        selectedAttachmentId = att.id
                                    },
                                    onDoubleClick: {
                                        store.openAttachment(att)
                                    },
                                    onDelete: {
                                        store.removeAttachment(attachmentId: att.id, fromTaskId: taskId)
                                        if selectedAttachmentId == att.id {
                                            selectedAttachmentId = nil
                                        }
                                    }
                                )
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
            
            // Helper text below
            Text("더블클릭: 열기 / 클릭 후 Del: 삭제")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 195)
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let fileURL = url else { return }
                DispatchQueue.main.async {
                    store.addAttachment(from: fileURL, toTaskId: taskId)
                }
            }
        }
    }
}

// MARK: - Attachment Item Row
struct AttachmentItemRow: View {
    let attachment: TaskAttachment
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering: Bool = false
    
    var icon: NSImage {
        let ext = (attachment.fileName as NSString).pathExtension
        if let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(attachment.fileDate.formattedDateString)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isHovering || isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("첨부파일 삭제")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovering ? Color.secondary.opacity(0.08) : Color(NSColor.textBackgroundColor)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { h in isHovering = h }
        .instantClick(
            onSingleClick: onSelect,
            onDoubleClick: onDoubleClick
        )
    }
}

// MARK: - Color Picker Palette View
struct ColorPickerPaletteView: View {
    @Binding var selectedHex: String
    var onSelect: (String) -> Void
    
    let colors = Palette.defaultColors
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("작업 테마 색상 선택 (하위 작업 일괄 반영)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 6), spacing: 8) {
                ForEach(colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: selectedHex == hex ? 2.5 : 0)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(radius: selectedHex == hex ? 2 : 0)
                        .contentShape(Circle())
                        .onTapGesture {
                            onSelect(hex)
                        }
                }
            }
        }
    }
}

// MARK: - Assignee Picker Popover View
struct AssigneePickerPopover: View {
    @ObservedObject var store: ProjectStore
    @Binding var assigneeIds: [UUID]
    var onToggle: (UUID) -> Void
    var onManage: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("작업자 선택")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button(action: onManage) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                        Text("관리")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderless)
                .help("새 작업자 등록 및 삭제")
            }
            
            Divider()
            
            if store.sortedAssignees.isEmpty {
                VStack(spacing: 8) {
                    Text("등록된 작업자가 없습니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("새 작업자 등록...") {
                        onManage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 6)
                .frame(width: 180)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.sortedAssignees) { assignee in
                        let isSelected = assigneeIds.contains(assignee.id)
                        
                        Button(action: {
                            onToggle(assignee.id)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 14))
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                
                                if let img = assignee.avatarImage {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 22, height: 22)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 22, height: 22)
                                        .foregroundColor(isSelected ? .accentColor : .secondary)
                                }
                                
                                Text(assignee.name)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 190)
            }
        }
        .padding(12)
    }
}

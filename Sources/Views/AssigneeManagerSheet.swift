import SwiftUI
import AppKit

struct AssigneeManagerSheet: View {
    @ObservedObject var store: ProjectStore
    let taskId: UUID?
    @Environment(\.dismiss) private var dismiss
    
    // Selection state for current task assignees
    @State private var selectedAssigneeIds: Set<UUID> = []
    // Currently highlighted assignee in the list for deletion or name edit
    @State private var focusedAssigneeId: UUID? = nil
    
    // New assignee input field
    @State private var newAssigneeName: String = ""
    @State private var showAddPopover: Bool = false
    
    private func toggleSelection(for id: UUID) {
        if selectedAssigneeIds.contains(id) {
            selectedAssigneeIds.remove(id)
        } else {
            selectedAssigneeIds.insert(id)
        }
        focusedAssigneeId = id
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("작업자 선택 및 관리")
                        .font(.system(size: 15, weight: .bold))
                    Text("작업에 배정할 작업자를 선택하거나 목록을 관리하세요.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // + / - buttons on the right
                HStack(spacing: 6) {
                    Button(action: {
                        showAddPopover = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showAddPopover) {
                        VStack(spacing: 12) {
                            Text("새 작업자 추가")
                                .font(.system(size: 13, weight: .bold))
                            TextField("작업자 이름", text: $newAssigneeName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                                .onSubmit {
                                    addNewAssignee()
                                }
                            HStack {
                                Button("취소") {
                                    showAddPopover = false
                                }
                                Button("추가") {
                                    addNewAssignee()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newAssigneeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding()
                    }
                    
                    Button(action: {
                        if let focused = focusedAssigneeId {
                            store.deleteAssignee(id: focused)
                            selectedAssigneeIds.remove(focused)
                            focusedAssigneeId = nil
                        }
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.bordered)
                    .disabled(focusedAssigneeId == nil)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Assignees List (가나다 순 정렬)
            List(selection: $focusedAssigneeId) {
                ForEach(store.sortedAssignees) { assignee in
                    HStack(spacing: 12) {
                        // Multi-selection Checkbox
                        Button(action: {
                            toggleSelection(for: assignee.id)
                        }) {
                            Image(systemName: selectedAssigneeIds.contains(assignee.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundColor(selectedAssigneeIds.contains(assignee.id) ? .accentColor : .secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .cursor(.pointingHand)
                        
                        // 32x32 Avatar (Click to toggle check, Double-click to pick new photo)
                        ZStack {
                            if let img = assignee.avatarImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.blue)
                                    )
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .cursor(.pointingHand)
                        .gesture(
                            TapGesture(count: 2).onEnded {
                                pickImageForAssignee(assignee)
                            }
                            .exclusively(before: TapGesture(count: 1).onEnded {
                                toggleSelection(for: assignee.id)
                            })
                        )
                        .help("클릭하여 선택/해제, 더블클릭하여 사진 변경")
                        
                        // Assignee Name
                        VStack(alignment: .leading, spacing: 2) {
                            Text(assignee.name)
                                .font(.system(size: 13, weight: .medium))
                            Text("더블클릭하여 사진 변경")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .contentShape(Rectangle())
                        .cursor(.pointingHand)
                        .onTapGesture {
                            toggleSelection(for: assignee.id)
                        }
                        
                        Spacer()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(for: assignee.id)
                            }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .tag(assignee.id)
                }
            }
            .listStyle(.inset)
            
            Divider()
            
            // Bottom Action Buttons ("취소", "확인")
            HStack {
                Text("\(selectedAssigneeIds.count)명 선택됨")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("취소") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("확인") {
                    // "확인을 누르면 선택한 작업자를 작업이름 화면 부분에 표시. 만약 아무도 고르지 않은 상태라면 작업 이름 화면에도 표시 안 함."
                    if let tId = taskId, var task = store.findTask(id: tId) {
                        task.assigneeIds = Array(selectedAssigneeIds)
                        store.updateTask(task)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 440, height: 420)
        .onAppear {
            if let tId = taskId, let task = store.findTask(id: tId) {
                self.selectedAssigneeIds = Set(task.assigneeIds)
            }
        }
    }
    
    private func addNewAssignee() {
        let trimmed = newAssigneeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addAssignee(name: trimmed)
        newAssigneeName = ""
        showAddPopover = false
    }
    
    private func pickImageForAssignee(_ assignee: Assignee) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image, .png, .jpeg]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.prompt = "이미지 선택"
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url, let data = try? Data(contentsOf: url) {
                // "이미지 크기는 32x32로 무조건 변경해서 보여줘야 함."
                // "작업자 이미지를 텍스트 형태로 변환한 후 저장파일 내에 넣도록 해."
                if let resizedData = Assignee.resizeImageData(data, targetSize: CGSize(width: 32, height: 32)) {
                    var updated = assignee
                    updated.avatarBase64 = resizedData.base64EncodedString()
                    store.updateAssignee(updated)
                }
            }
        }
    }
}

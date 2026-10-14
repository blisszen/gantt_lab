import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Translation

struct AssigneeExportSheet: View {
    @ObservedObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedAssigneeId: UUID? = nil
    @State private var errorMessage: String? = nil
    @State private var isExporting: Bool = false
    @State private var translationConfig: TranslationSession.Configuration? = nil
    
    private var dateRangeString: String {
        let range = store.exportDateRange()
        return "\(range.start.formattedDateString) ~ \(range.end.formattedDateString)"
    }
    
    private var selectedAssignee: Assignee? {
        if let id = selectedAssigneeId {
            return store.project.assignees.first(where: { $0.id == id })
        }
        return store.project.assignees.first
    }
    
    private var previewRows: [ExportTaskRow] {
        guard let assignee = selectedAssignee else { return [] }
        return store.flattenedExportRows(assigneeId: assignee.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "tablecells.badge.ellipsis")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("작업자 별 할일 엑셀 저장")
                        .font(.system(size: 16, weight: .bold))
                    Text("선택한 작업자가 참여하는 향후 1달 이내(\(dateRangeString))의 작업을 계층 구조와 함께 엑셀 파일(.xlsx)로 내보냅니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
            
            if store.project.assignees.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("프로젝트에 등록된 작업자가 없습니다.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("상단 툴바의 '작업자' 버튼을 눌러 작업자를 먼저 추가해주세요.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                    
                    HStack {
                        Spacer()
                        Button("닫기") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    .padding(20)
                }
                .frame(width: 620, height: 350)
            } else {
                HStack(spacing: 0) {
                    // Left Column: Assignee Selector List
                    VStack(alignment: .leading, spacing: 8) {
                        Text("작업자 선택 (1명)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(store.sortedAssignees) { assignee in
                                    let isSelected = (selectedAssignee?.id == assignee.id)
                                    let count = store.flattenedExportRows(assigneeId: assignee.id).count
                                    
                                    Button(action: {
                                        selectedAssigneeId = assignee.id
                                    }) {
                                        HStack(spacing: 10) {
                                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
                                                .font(.system(size: 14))
                                            
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
                                            
                                            Text(assignee.name)
                                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            if count > 0 {
                                                Text("\(count)개 작업")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                                    .cornerRadius(4)
                                            } else {
                                                Text("대상 없음")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary.opacity(0.5))
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                    }
                    .frame(width: 220)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    
                    Divider()
                    
                    // Right Column: Export Preview
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            if let a = selectedAssignee {
                                Text("\(a.name) 님의 할일 목록")
                                    .font(.system(size: 13, weight: .bold))
                                
                                if a.isEnglishName {
                                    HStack(spacing: 4) {
                                        Image(systemName: "globe")
                                            .font(.system(size: 9))
                                        Text("한영 병행 표기")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                                }
                                
                                Spacer()
                                Text("총 \(previewRows.count)개 작업")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        
                        Divider()
                        
                        if previewRows.isEmpty {
                            VStack(spacing: 10) {
                                Spacer()
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("선택한 작업자에게 할당된 향후 1달 이내의 작업이 없습니다.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(previewRows) { row in
                                        let isRoot = (row.level == 0)
                                        HStack(spacing: 8) {
                                            // Indented tree layout
                                            HStack(spacing: 4) {
                                                if row.level > 0 {
                                                    Text(String(repeating: "└", count: row.level))
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.secondary.opacity(0.7))
                                                }
                                                
                                                Circle()
                                                    .fill(Color(hex: row.task.colorHex))
                                                    .frame(width: 7, height: 7)
                                                
                                                Text(row.task.title)
                                                    .font(.system(size: 12, weight: isRoot ? .bold : .regular))
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 220, alignment: .leading)
                                            
                                            // Period
                                            Text("\(row.task.startDate.formattedDateString) ~ \(row.task.effectiveEndDate.formattedDateString)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .frame(width: 150, alignment: .leading)
                                            
                                            // Status
                                            Text(row.task.isCompleted ? "완료" : "진행중")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(row.task.isCompleted ? .green : .blue)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background((row.task.isCompleted ? Color.green : Color.blue).opacity(0.12))
                                                .cornerRadius(3)
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(isRoot ? Color.secondary.opacity(0.04) : Color.clear)
                                        
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 680, height: 380)
                
                Divider()
                
                // Footer Buttons
                HStack {
                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            store.showExportAllAssigneesSheet = true
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "archivebox")
                            Text("모든 작업자 일괄 저장 (ZIP)...")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExporting)
                    
                    Button("취소") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isExporting)
                    
                    Button(action: {
                        exportToExcel()
                    }) {
                        HStack(spacing: 6) {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                            }
                            Text("엑셀(.xlsx) 파일로 저장...")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedAssignee == nil || previewRows.isEmpty || isExporting)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .onAppear {
            if selectedAssigneeId == nil {
                selectedAssigneeId = store.sortedAssignees.first?.id
            }
            if translationConfig == nil {
                if #available(macOS 15.0, *) {
                    translationConfig = TranslationSession.Configuration(
                        source: Locale.Language(identifier: "ko"),
                        target: Locale.Language(identifier: "en")
                    )
                }
            }
        }
        .translationTask(translationConfig) { session in
            TranslationService.shared.activeSession = session
        }
    }
    
    private func exportToExcel() {
        guard let assignee = selectedAssignee else { return }
        let rows = previewRows
        guard !rows.isEmpty else { return }
        
        let savePanel = NSSavePanel()
        savePanel.title = "작업자 별 할일 엑셀 저장"
        let dateSuffix = Date().formattedDateString.replacingOccurrences(of: "-", with: "")
        savePanel.nameFieldStringValue = "\(assignee.name)_할일목록_\(dateSuffix).xlsx"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        savePanel.canCreateDirectories = true
        
        if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
            isExporting = true
            errorMessage = nil
            
            Task {
                do {
                    var translatedTitles: [UUID: String] = [:]
                    var translatedNotes: [UUID: String] = [:]
                    
                    if assignee.isEnglishName {
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
                    
                    try ExcelExporter.exportTasks(
                        assignee: assignee,
                        project: store.project,
                        exportRows: rows,
                        destinationURL: destinationURL,
                        translatedTitles: translatedTitles,
                        translatedNotes: translatedNotes
                    )
                    
                    await MainActor.run {
                        isExporting = false
                        dismiss()
                        
                        // Show completion modal
                        let alert = NSAlert()
                        alert.messageText = "엑셀 파일 저장 완료"
                        let bilingualNote = assignee.isEnglishName ? " (영문 병행 표기 적용)" : ""
                        alert.informativeText = "\(assignee.name) 님의 할일 목록(\(rows.count)개 작업)이 성공적으로 엑셀 파일로 저장되었습니다.\(bilingualNote)\n\n저장 경로: \(destinationURL.lastPathComponent)"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "Finder에서 보기")
                        alert.addButton(withTitle: "확인")
                        let resp = alert.runModal()
                        if resp == .alertFirstButtonReturn {
                            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                        }
                    }
                } catch {
                    await MainActor.run {
                        isExporting = false
                        errorMessage = "저장 실패: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Translation

struct AllAssigneesExportSheet: View {
    @ObservedObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var isExporting: Bool = false
    @State private var progressStatus: String = ""
    @State private var progressValue: Double = 0.0
    @State private var errorMessage: String? = nil
    
    // SwiftUI Translation Configuration for Apple on-device translation
    @State private var translationConfig: TranslationSession.Configuration? = nil
    
    private var dateRangeString: String {
        let range = store.exportDateRange()
        return "\(range.start.formattedDateString) ~ \(range.end.formattedDateString)"
    }
    
    /// Target assignees that have at least one task in the target date range
    private var assigneesWithTasks: [(assignee: Assignee, count: Int)] {
        store.sortedAssignees.compactMap { a in
            let count = store.flattenedExportRows(assigneeId: a.id).count
            return count > 0 ? (a, count) : nil
        }
    }
    
    private var englishAssigneesCount: Int {
        assigneesWithTasks.filter { $0.assignee.isEnglishName }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.8), Color.teal.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("모든 작업자별 할일 저장")
                        .font(.system(size: 17, weight: .bold))
                    Text("향후 1달 이내(\(dateRangeString))의 할일을 작업자별 엑셀 파일로 생성 후 하나의 ZIP 파일로 압축합니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            
            Divider()
            
            if assigneesWithTasks.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("저장할 작업자가 없습니다.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("향후 1달 이내에 등록된 작업이 있는 작업자가 없습니다.")
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
                .frame(width: 580, height: 320)
            } else {
                // Main Content
                VStack(spacing: 14) {
                    // Summary info cards
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.accentColor)
                            Text("대상 작업자: 총 \(assigneesWithTasks.count)명")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                        
                        if englishAssigneesCount > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "character.book.closed.fill")
                                    .foregroundColor(.blue)
                                Text("영문 작업자: \(englishAssigneesCount)명 (한영 병행 번역)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // Notice banner for bilingual translation
                    if englishAssigneesCount > 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 13))
                            Text("작업자 이름이 영문인 경우, 엑셀 파일의 모든 내용(작업명, 상세 메모, 표 헤더, 상태 등)이 영어와 한글로 병행 표기됩니다.")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(6)
                        .padding(.horizontal, 24)
                    }
                    
                    // Assignee List
                    VStack(alignment: .leading, spacing: 6) {
                        Text("포함될 작업자 목록")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                        
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(assigneesWithTasks, id: \.assignee.id) { item in
                                    let assignee = item.assignee
                                    let count = item.count
                                    let isEng = assignee.isEnglishName
                                    
                                    HStack(spacing: 12) {
                                        if let img = assignee.avatarImage {
                                            Image(nsImage: img)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 26, height: 26)
                                                .clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .frame(width: 26, height: 26)
                                                .foregroundColor(isEng ? .blue.opacity(0.8) : .green.opacity(0.8))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(assignee.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)
                                        }
                                        
                                        Spacer()
                                        
                                        if isEng {
                                            HStack(spacing: 4) {
                                                Image(systemName: "globe")
                                                    .font(.system(size: 9))
                                                Text("한영 병행 표기")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                        } else {
                                            Text("한국어")
                                                .font(.system(size: 10))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.secondary.opacity(0.1))
                                                .foregroundColor(.secondary)
                                                .cornerRadius(4)
                                        }
                                        
                                        Text("\(count)개 작업")
                                            .font(.system(size: 11, weight: .semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                    )
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                        }
                    }
                    .frame(height: 200)
                }
                .frame(width: 600)
                
                Divider()
                
                // Footer
                HStack {
                    if let err = errorMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(err)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Button("취소") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isExporting)
                    
                    Button(action: {
                        startAllAssigneesExport()
                    }) {
                        HStack(spacing: 6) {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "archivebox.fill")
                            }
                            Text("ZIP 파일로 압축 저장...")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting || assigneesWithTasks.isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView(value: progressValue, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(width: 280)
                        
                        Text(progressStatus)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .shadow(radius: 12)
                    )
                }
            }
        }
        .onAppear {
            setupTranslationSessionIfNeeded()
        }
        // Native Apple Translation Task attached to view
        .translationTask(translationConfig) { session in
            TranslationService.shared.activeSession = session
        }
    }
    
    private func setupTranslationSessionIfNeeded() {
        if translationConfig == nil {
            if #available(macOS 15.0, *) {
                translationConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "ko"),
                    target: Locale.Language(identifier: "en")
                )
            }
        }
    }
    
    private func startAllAssigneesExport() {
        let savePanel = NSSavePanel()
        savePanel.title = "모든 작업자별 할일 저장 (ZIP)"
        let projName = store.project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeProj = projName.isEmpty ? "Gantt" : projName
        let dateSuffix = Date().formattedDateString.replacingOccurrences(of: "-", with: "")
        savePanel.nameFieldStringValue = "\(safeProj)_모든작업자_할일목록_\(dateSuffix).zip"
        savePanel.allowedContentTypes = [UTType.zip, UTType(filenameExtension: "zip") ?? .data]
        savePanel.canCreateDirectories = true
        
        if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
            isExporting = true
            progressStatus = "저장 준비 중..."
            progressValue = 0.0
            errorMessage = nil
            
            Task {
                do {
                    let count = try await store.executeAllAssigneesZipExport(destinationZipURL: destinationURL) { status, prog in
                        DispatchQueue.main.async {
                            self.progressStatus = status
                            self.progressValue = prog
                        }
                    }
                    
                    await MainActor.run {
                        self.isExporting = false
                        self.dismiss()
                        
                        // Show completion alert
                        let alert = NSAlert()
                        alert.messageText = "모든 작업자별 할일 저장 완료"
                        alert.informativeText = "총 \(count)명의 작업자별 할일 엑셀 파일이 성공적으로 생성되어 하나의 ZIP 파일로 압축되었습니다.\n개별 엑셀 파일은 임시 보관 후 정리되었습니다.\n\n저장 경로: \(destinationURL.lastPathComponent)"
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
                        self.isExporting = false
                        self.errorMessage = "저장 실패: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

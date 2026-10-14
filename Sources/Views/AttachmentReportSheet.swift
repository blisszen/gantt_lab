import SwiftUI
import AppKit

struct AttachmentIntegrityReport: Identifiable, Equatable {
    var id = UUID()
    var removedBrokenLinks: [(taskTitle: String, fileName: String)] = []
    var removedOrphanFiles: [String] = []
    
    var hasChanges: Bool {
        !removedBrokenLinks.isEmpty || !removedOrphanFiles.isEmpty
    }
    
    static func == (lhs: AttachmentIntegrityReport, rhs: AttachmentIntegrityReport) -> Bool {
        lhs.id == rhs.id
    }
}

struct AttachmentReportSheet: View {
    let report: AttachmentIntegrityReport
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("첨부파일 무결성 검사 결과 보고")
                        .font(.system(size: 15, weight: .bold))
                    Text("프로젝트를 여는 중 일치하지 않는 파일 및 링크가 정리되었습니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Section 1: Removed Broken Links
                    if !report.removedBrokenLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "link.badge.plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red)
                                Text("실제 파일이 사라져 삭제된 첨부링크 (\(report.removedBrokenLinks.count)건)")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            
                            VStack(spacing: 4) {
                                ForEach(Array(report.removedBrokenLinks.enumerated()), id: \.offset) { _, item in
                                    HStack(spacing: 8) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.red.opacity(0.8))
                                        
                                        Text(item.taskTitle)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                        
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        
                                        Text(item.fileName)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // Section 2: Removed Orphan Files
                    if !report.removedOrphanFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.orange)
                                Text("연결된 작업이 없어 디스크에서 삭제된 파일 (\(report.removedOrphanFiles.count)건)")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            
                            VStack(spacing: 4) {
                                ForEach(report.removedOrphanFiles, id: \.self) { fileName in
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.badge.arrow.up")
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                        
                                        Text(fileName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Text("삭제됨")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 340)
            
            Divider()
            
            HStack {
                Spacer()
                Button("확인") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 480, maxWidth: 540)
    }
}

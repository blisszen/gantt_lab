import SwiftUI

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Header: App Icon & Name
            HStack(spacing: 16) {
                ZStack {
                    if let nsImage = NSImage(contentsOfFile: "project.png") {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gantt Lab")
                        .font(.system(size: 20, weight: .bold))
                    
                    Text("버전 \(currentVersion)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("고성능 네이티브 Gantt Chart 일정 관리 도구")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.85))
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // Picker Tab (주요 기능 / 단축키 안내)
            Picker("", selection: $selectedTab) {
                Text("주요 기능").tag(0)
                Text("단축키 안내").tag(1)
            }
            .pickerStyle(.segmented)
            
            // Tab Content
            if selectedTab == 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Gantt Lab은 Mac 환경에서 간트 차트를 손쉽게 작성, 시각화, 편집할 수 있는 강력한 프로젝트 일정 관리 도구입니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(icon: "list.bullet.indent", text: "트리 구조의 계층형 작업 관리 및 실시간 레벨 이동")
                        FeatureRow(icon: "arrow.left.and.right", text: "타임라인 Bar 실시간 드래그 & 시작/종료일 리사이징")
                        FeatureRow(icon: "arrow.triangle.turn.up.right.diamond.fill", text: "Shift+클릭 선후행 의존성 화살표 연결 및 일정 자동 연동")
                        FeatureRow(icon: "person.3.fill", text: "32x32 작업자 배정 및 날짜별 참여 워크로드 시각화")
                        FeatureRow(icon: "arrow.up.and.down.square", text: "⌘↑, ⌘↓ 단축키로 작업 순서 상하 자유 이동")
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .frame(height: 220, alignment: .top)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ShortcutRow(key: "⌘ + ↑", desc: "작업 순서 위로 이동 (Move Task Up)")
                        ShortcutRow(key: "⌘ + ↓", desc: "작업 순서 아래로 이동 (Move Task Down)")
                        ShortcutRow(key: "⌘ + →", desc: "하위 레벨로 들여쓰기 (Indent)")
                        ShortcutRow(key: "⌘ + ←", desc: "상위 레벨로 내어쓰기 (Outdent)")
                        ShortcutRow(key: "⇧ + Return", desc: "동일 레벨 새 작업 연속 추가 (Shift-Enter)")
                        ShortcutRow(key: "Return", desc: "선택한 작업 이름 인라인 편집")
                        ShortcutRow(key: "Delete", desc: "선택한 작업 및 하위 작업 삭제")
                        ShortcutRow(key: "⌘ + Z", desc: "실행 취소 (최대 10단계 Undo)")
                        ShortcutRow(key: "⇧ + 클릭", desc: "Bar 간 선후행 의존성 화살표 연결/토글")
                        ShortcutRow(key: "← / →", desc: "선택한 작업 일정 1일 앞/뒤로 이동")
                        ShortcutRow(key: "⌘ + S", desc: "프로젝트 파일 저장")
                    }
                    .padding(8)
                }
                .frame(height: 220)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            HStack {
                Spacer()
                Button("확인") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.system(size: 11))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.primary)
        }
    }
}

struct ShortcutRow: View {
    let key: String
    let desc: String
    
    var body: some View {
        HStack {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            
            Spacer()
            
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

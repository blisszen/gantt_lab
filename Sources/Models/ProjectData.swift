import Foundation

struct ProjectData: Codable {
    var version: String = "1.0"
    var title: String = "새 프로젝트"
    var tasks: [TaskItem] = []
    var dependencies: [Dependency] = []
    var assignees: [Assignee] = []
    
    static func createSampleProject() -> ProjectData {
        let today = Date().startOfDay
        let assignees = Assignee.defaultAssignees
        
        let a1 = assignees[0].id
        let a2 = assignees[1].id
        let a3 = assignees[2].id
        let a4 = assignees[3].id
        
        let task1 = TaskItem(
            title: "요구사항 분석 및 기획",
            startDate: today,
            endDate: today.addingDays(5),
            isCompleted: true,
            colorHex: "#3B82F6",
            assigneeIds: [a1, a2],
            notes: "# 요구사항 분석\n- 클라이언트 인터뷰 진행\n- 요구사항 명세서 작성 완료",
            isExpanded: true,
            children: [
                TaskItem(
                    title: "기능 명세 작성",
                    startDate: today,
                    endDate: today.addingDays(2),
                    isCompleted: true,
                    colorHex: "#3B82F6",
                    assigneeIds: [a1],
                    notes: "핵심 기능 리스트 정의"
                ),
                TaskItem(
                    title: "화면 와이어프레임 설계",
                    startDate: today.addingDays(2),
                    endDate: today.addingDays(5),
                    isCompleted: true,
                    colorHex: "#3B82F6",
                    assigneeIds: [a2],
                    notes: "UI 레이아웃 초안 구성"
                )
            ]
        )
        
        let task2 = TaskItem(
            title: "UI/UX 디자인 및 프로토타입",
            startDate: today.addingDays(5),
            endDate: today.addingDays(12),
            isCompleted: false,
            colorHex: "#10B981",
            assigneeIds: [a2, a3],
            notes: "Figma를 활용한 디자인 시스템 구축 및 화면 디자인",
            isExpanded: true,
            children: [
                TaskItem(
                    title: "디자인 시스템 컴포넌트",
                    startDate: today.addingDays(5),
                    endDate: today.addingDays(8),
                    isCompleted: false,
                    colorHex: "#10B981",
                    assigneeIds: [a2]
                ),
                TaskItem(
                    title: "인터랙티브 프로토타입",
                    startDate: today.addingDays(8),
                    endDate: today.addingDays(12),
                    isCompleted: false,
                    colorHex: "#10B981",
                    assigneeIds: [a3]
                )
            ]
        )
        
        let task3 = TaskItem(
            title: "프론트엔드 및 백엔드 개발",
            startDate: today.addingDays(10),
            endDate: today.addingDays(22),
            isCompleted: false,
            colorHex: "#F59E0B",
            assigneeIds: [a1, a3, a4],
            notes: "SwiftUI 아키텍처 구현 및 Gantt 렌더링 최적화",
            isExpanded: true,
            children: [
                TaskItem(
                    title: "데이터 모델 & 스토리지 엔진",
                    startDate: today.addingDays(10),
                    endDate: today.addingDays(15),
                    isCompleted: false,
                    colorHex: "#F59E0B",
                    assigneeIds: [a1]
                ),
                TaskItem(
                    title: "Gantt 차트 타임라인 드래그 & 의존성",
                    startDate: today.addingDays(14),
                    endDate: today.addingDays(20),
                    isCompleted: false,
                    colorHex: "#F59E0B",
                    assigneeIds: [a3, a4]
                ),
                TaskItem(
                    title: "작업자 워크로드 시각화",
                    startDate: today.addingDays(18),
                    endDate: today.addingDays(22),
                    isCompleted: false,
                    colorHex: "#F59E0B",
                    assigneeIds: [a4]
                )
            ]
        )
        
        let task4 = TaskItem(
            title: "QA 테스트 및 배포 준비",
            startDate: today.addingDays(22),
            endDate: today.addingDays(28),
            isCompleted: false,
            colorHex: "#8B5CF6",
            assigneeIds: [a1, a2, a4],
            notes: "통합 테스트 및 버그 수정, 릴리즈 빌드 패키징"
        )
        
        let taskMilestone = TaskItem(
            title: "v1.0 릴리즈 마일스톤",
            startDate: today.addingDays(28),
            endDate: today.addingDays(28),
            isCompleted: false,
            colorHex: "#EF4444",
            assigneeIds: [a1, a3],
            notes: "정식 v1.0 프로덕션 배포 완료 마일스톤",
            isMilestone: true
        )
        
        let dependencies = [
            Dependency(fromTaskId: task1.id, toTaskId: task2.id),
            Dependency(fromTaskId: task2.id, toTaskId: task3.id),
            Dependency(fromTaskId: task3.id, toTaskId: task4.id),
            Dependency(fromTaskId: task4.id, toTaskId: taskMilestone.id)
        ]
        
        return ProjectData(
            version: "1.0",
            title: "Gantt Lab 프로젝트",
            tasks: [task1, task2, task3, task4, taskMilestone],
            dependencies: dependencies,
            assignees: assignees
        )
    }
}

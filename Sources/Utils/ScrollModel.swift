import SwiftUI
import Observation
import QuartzCore

// MARK: - Scroll Model (Performance-isolated scroll state)
// 스크롤 위치를 ProjectStore(@Published)에서 분리한 전용 모델.
// - Observation(@Observable)은 "속성 단위"로 의존성을 추적하므로,
//   x / y 를 실제로 읽는 작은 View(ScrollOffsetView, 스크롤바)만 매 프레임 갱신된다.
// - 가상화(보이는 범위만 렌더링)에 쓰이는 xBucket / yBucket 은 일정 구간을 넘을 때만 바뀌므로
//   무거운 레이어(행, 날짜 헤더, 워크로드 셀)는 스크롤 중에도 거의 재계산되지 않는다.
// - settledX 는 스크롤이 멈춘 뒤에만 갱신되며, Bar의 히트테스트/리사이즈 핸들 노출 판정에 사용된다.
@MainActor
@Observable
final class ScrollModel {
    /// Gantt / Workload 공통 가로 스크롤 오프셋
    private(set) var x: CGFloat = 0
    /// Gantt / 트리 공통 세로 스크롤 오프셋
    private(set) var y: CGFloat = 0
    /// 워크로드 패널 세로 스크롤 오프셋
    private(set) var workloadY: CGFloat = 0
    
    /// 가로 가상화 구간 번호 (xBucketUnit 픽셀마다 1 증가)
    private(set) var xBucket: Int = 0
    /// 세로 가상화 구간 번호 (yBucketUnit 픽셀마다 1 증가)
    private(set) var yBucket: Int = 0
    /// 스크롤이 멈춘 뒤의 가로 오프셋 (히트테스트 판정용, 매 프레임 갱신되지 않음)
    private(set) var settledX: CGFloat = 0
    
    /// 가로 가상화 구간 크기(일 단위)
    @ObservationIgnored static let daysPerBucket: Int = 15
    /// 세로 가상화 구간 크기(행 단위)
    @ObservationIgnored static let rowsPerBucket: Int = 10
    
    @ObservationIgnored private(set) var xBucketUnit: CGFloat = 36.0 * CGFloat(ScrollModel.daysPerBucket)
    @ObservationIgnored private(set) var yBucketUnit: CGFloat = 38.0 * CGFloat(ScrollModel.rowsPerBucket)
    
    @ObservationIgnored private var lastXChangeTime: CFTimeInterval = 0
    @ObservationIgnored private var settleTask: Task<Void, Never>? = nil
    
    init() {}
    
    // MARK: Setters (값이 실제로 바뀔 때만 관찰자에게 알림)
    func setX(_ newValue: CGFloat) {
        guard newValue != x else { return }
        x = newValue
        updateXBucket()
        scheduleSettle()
    }
    
    func setY(_ newValue: CGFloat) {
        guard newValue != y else { return }
        y = newValue
        updateYBucket()
    }
    
    func setWorkloadY(_ newValue: CGFloat) {
        guard newValue != workloadY else { return }
        workloadY = newValue
    }
    
    /// 줌(dayWidth) 변경 시 가로 구간 크기 갱신
    func configure(dayWidth: CGFloat, rowHeight: CGFloat) {
        let newXUnit = max(1, dayWidth * CGFloat(Self.daysPerBucket))
        let newYUnit = max(1, rowHeight * CGFloat(Self.rowsPerBucket))
        if newXUnit != xBucketUnit {
            xBucketUnit = newXUnit
            updateXBucket()
        }
        if newYUnit != yBucketUnit {
            yBucketUnit = newYUnit
            updateYBucket()
        }
    }
    
    private func updateXBucket() {
        let b = Int(floor(max(0, x) / xBucketUnit))
        if b != xBucket { xBucket = b }
    }
    
    private func updateYBucket() {
        let b = Int(floor(max(0, y) / yBucketUnit))
        if b != yBucket { yBucket = b }
    }
    
    /// 마지막 가로 스크롤 후 약 0.1초간 변화가 없으면 settledX 를 확정
    private func scheduleSettle() {
        lastXChangeTime = CACurrentMediaTime()
        guard settleTask == nil else { return }
        settleTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard let self else { return }
                if CACurrentMediaTime() - self.lastXChangeTime >= 0.1 {
                    self.settleTask = nil
                    if self.settledX != self.x {
                        self.settledX = self.x
                    }
                    return
                }
            }
        }
    }
    
    // MARK: Virtualization Windows
    /// 현재 가로 구간 기준으로 렌더링할 날짜 범위 (앞뒤로 1구간씩 여유)
    func dayWindow(viewportWidth: CGFloat, dayWidth: CGFloat, totalDays: Int) -> Range<Int> {
        guard totalDays > 0, dayWidth > 0 else { return 0..<0 }
        let per = Self.daysPerBucket
        let visibleDays = Int(ceil(viewportWidth / dayWidth))
        let start = max(0, min(totalDays, (xBucket - 1) * per))
        let end = max(start, min(totalDays, (xBucket + 2) * per + visibleDays))
        return start..<end
    }
    
    /// 현재 세로 구간 기준으로 렌더링할 행 범위 (앞뒤로 1구간씩 여유)
    func rowWindow(viewportHeight: CGFloat, rowHeight: CGFloat, totalRows: Int) -> Range<Int> {
        guard totalRows > 0, rowHeight > 0 else { return 0..<0 }
        let per = Self.rowsPerBucket
        let visibleRows = Int(ceil(viewportHeight / rowHeight))
        let start = max(0, min(totalRows, (yBucket - 1) * per))
        let end = max(start, min(totalRows, (yBucket + 2) * per + visibleRows))
        return start..<end
    }
    
    /// 가로 스크롤 가능 범위 계산에 쓰는 "현재 구간의 최대 x" (구간이 바뀔 때만 변함)
    var xBucketUpperBound: CGFloat {
        CGFloat(xBucket + 1) * xBucketUnit
    }
}

// MARK: - Scroll Offset Container
/// 스크롤 오프셋을 "읽는" 유일한 View.
/// content 는 부모가 만든 값을 그대로 보관하므로, 스크롤 중에는 이 View의 body(offset 적용)만 재평가되고
/// content 내부(행/헤더/셀)는 입력이 바뀌지 않아 다시 계산되지 않는다.
struct ScrollOffsetView<Content: View>: View {
    enum VerticalSource {
        case none
        case gantt
        case workload
    }
    
    let scroll: ScrollModel
    var horizontal: Bool = true
    var vertical: VerticalSource = .none
    var baseX: CGFloat = 0
    var baseY: CGFloat = 0
    @ViewBuilder let content: Content
    
    var body: some View {
        let dx: CGFloat = horizontal ? (baseX - scroll.x) : baseX
        let dy: CGFloat
        switch vertical {
        case .none: dy = baseY
        case .gantt: dy = baseY - scroll.y
        case .workload: dy = baseY - scroll.workloadY
        }
        return content.offset(x: dx, y: dy)
    }
}

// MARK: - Precomputed Timeline Day Info
/// 날짜 헤더/그리드/워크로드에서 매 프레임 반복되던 Calendar·DateFormatter 연산을
/// 한 번만 계산해 캐시하기 위한 날짜 메타데이터.
struct TimelineDay: Identifiable, Equatable {
    let index: Int
    let date: Date
    let dayNumber: Int
    let isWeekend: Bool
    let isToday: Bool
    /// "yyyy-MM" (월 첫날 / 첫 열에 표시)
    let monthLabel: String
    /// "M/d"
    let shortLabel: String
    /// "E" (요일)
    let weekdayLabel: String
    
    var id: Int { index }
    var showsMonthLabel: Bool { dayNumber == 1 || index == 0 }
}

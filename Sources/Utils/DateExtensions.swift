import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self.startOfDay) ?? self
    }
    
    func daysBetween(_ other: Date) -> Int {
        let from = self.startOfDay
        let to = other.startOfDay
        let components = Calendar.current.dateComponents([.day], from: from, to: to)
        return components.day ?? 0
    }
    
    // MARK: - Cached Formatters
    // DateFormatter 생성은 매우 비싸므로 한 번만 만들어 재사용한다.
    // (macOS 10.9+ 에서 DateFormatter 의 string(from:) 은 스레드 안전)
    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter
    }
    private static let fullDateFormatter = makeFormatter("yyyy-MM-dd")
    private static let shortDateFormatter = makeFormatter("M/d")
    private static let dayOfWeekFormatter = makeFormatter("E")
    
    var formattedDateString: String {
        Date.fullDateFormatter.string(from: self)
    }
    
    var shortDateString: String {
        Date.shortDateFormatter.string(from: self)
    }
    
    var dayOfWeekString: String {
        Date.dayOfWeekFormatter.string(from: self)
    }
    
    var dayNumber: Int {
        Calendar.current.component(.day, from: self)
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isWeekend: Bool {
        let weekday = Calendar.current.component(.weekday, from: self)
        return weekday == 1 || weekday == 7 // 1: Sunday, 7: Saturday
    }
    
    static func parse(string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd"
        if let d = formatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return d.startOfDay
        }
        // Try other common formats
        formatter.dateFormat = "yyyy.MM.dd"
        if let d = formatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return d.startOfDay
        }
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))?.startOfDay
    }
}

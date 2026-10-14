import Foundation
import SwiftUI

struct TaskAttachment: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var fileName: String        // Stored file name inside the Attachments folder
    var originalName: String    // Original file name prior to deduplication
    var fileDate: Date          // File creation/modification date
    var fileSize: Int64         // Size in bytes
    
    init(
        id: UUID = UUID(),
        fileName: String,
        originalName: String? = nil,
        fileDate: Date = Date(),
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.fileName = fileName
        self.originalName = originalName ?? fileName
        self.fileDate = fileDate
        self.fileSize = fileSize
    }
}

struct TaskItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var startDate: Date
    var endDate: Date
    var isCompleted: Bool = false
    var colorHex: String = Palette.defaultColor
    var assigneeIds: [UUID] = []
    var notes: String = ""
    var isExpanded: Bool = true
    var children: [TaskItem] = []
    var isMilestone: Bool = false
    var attachments: [TaskAttachment] = []
    
    enum CodingKeys: String, CodingKey {
        case id, title, startDate, endDate, isCompleted, colorHex, assigneeIds, notes, isExpanded, children
        case isMilestone, attachments
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date = Date().startOfDay,
        endDate: Date = Date().startOfDay.addingDays(7),
        isCompleted: Bool = false,
        colorHex: String = Palette.defaultColor,
        assigneeIds: [UUID] = [],
        notes: String = "",
        isExpanded: Bool = true,
        children: [TaskItem] = [],
        isMilestone: Bool = false,
        attachments: [TaskAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate.startOfDay
        if isMilestone {
            self.endDate = startDate.startOfDay
        } else {
            let validEndDate = endDate.startOfDay
            self.endDate = validEndDate >= startDate.startOfDay ? validEndDate : startDate.startOfDay.addingDays(1)
        }
        self.isCompleted = isCompleted
        self.colorHex = colorHex
        self.assigneeIds = assigneeIds
        self.notes = notes
        self.isExpanded = isExpanded
        self.children = isMilestone ? [] : children
        self.isMilestone = isMilestone
        self.attachments = attachments
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        let s = try container.decode(Date.self, forKey: .startDate).startOfDay
        self.startDate = s
        let isM = try container.decodeIfPresent(Bool.self, forKey: .isMilestone) ?? false
        self.isMilestone = isM
        if isM {
            self.endDate = s
        } else {
            let e = try container.decode(Date.self, forKey: .endDate).startOfDay
            self.endDate = e >= s ? e : s.addingDays(1)
        }
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? Palette.defaultColor
        self.assigneeIds = try container.decodeIfPresent([UUID].self, forKey: .assigneeIds) ?? []
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        self.children = try container.decodeIfPresent([TaskItem].self, forKey: .children) ?? []
        self.attachments = try container.decodeIfPresent([TaskAttachment].self, forKey: .attachments) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(assigneeIds, forKey: .assigneeIds)
        try container.encode(notes, forKey: .notes)
        try container.encode(isExpanded, forKey: .isExpanded)
        try container.encode(children, forKey: .children)
        try container.encode(isMilestone, forKey: .isMilestone)
        try container.encode(attachments, forKey: .attachments)
    }
    
    var effectiveStartDate: Date {
        if isMilestone || children.isEmpty {
            return startDate
        }
        var minDate = startDate
        for child in children {
            let childStart = child.effectiveStartDate
            if childStart < minDate {
                minDate = childStart
            }
        }
        return minDate
    }
    
    var effectiveEndDate: Date {
        if isMilestone || children.isEmpty {
            return isMilestone ? startDate : endDate
        }
        var maxDate = endDate
        for child in children {
            let childEnd = child.effectiveEndDate
            if childEnd > maxDate {
                maxDate = childEnd
            }
        }
        return maxDate
    }
    
    var effectiveDateRange: (start: Date, end: Date) {
        if isMilestone {
            return (startDate, startDate)
        }
        let s = effectiveStartDate
        let e = effectiveEndDate
        return (s, max(s, e))
    }
    
    var durationDays: Int {
        if isMilestone {
            return 1
        }
        let range = effectiveDateRange
        return max(1, range.start.daysBetween(range.end) + 1)
    }
    
    // Recursive color applicator for self and all descendants
    mutating func applyColorRecursively(_ hex: String) {
        self.colorHex = hex
        for i in 0..<children.count {
            children[i].applyColorRecursively(hex)
        }
    }
    
    // Shift dates by delta days for self and all descendants
    mutating func shiftDatesRecursively(days: Int) {
        self.startDate = self.startDate.addingDays(days)
        if isMilestone {
            self.endDate = self.startDate
        } else {
            self.endDate = self.endDate.addingDays(days)
        }
        for i in 0..<children.count {
            children[i].shiftDatesRecursively(days: days)
        }
    }
    
    // Extend or shrink duration by delta days (adjusts endDate)
    mutating func adjustEndDate(byDays days: Int) {
        guard !isMilestone else { return }
        let newEnd = self.endDate.addingDays(days)
        if newEnd >= self.startDate {
            self.endDate = newEnd
        }
    }
}

// Helper struct for flattened tree rows to easily render in SwiftUI with indentations
struct FlattenedTaskRow: Identifiable {
    var id: UUID { task.id }
    var task: TaskItem
    var level: Int
    var parentId: UUID?
    var hasChildren: Bool { !task.children.isEmpty }
    var isExpanded: Bool { task.isExpanded }
}

struct ExportTaskRow: Identifiable {
    var id: UUID { task.id }
    var task: TaskItem
    var level: Int
    var hasChildren: Bool { !task.children.isEmpty }
}

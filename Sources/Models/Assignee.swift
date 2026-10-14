import Foundation
import AppKit
import SwiftUI

struct Assignee: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var avatarBase64: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarBase64
        case avatarData
    }
    
    init(id: UUID = UUID(), name: String, avatarBase64: String? = nil, avatarData: Data? = nil) {
        self.id = id
        self.name = name
        if let base64 = avatarBase64 {
            self.avatarBase64 = base64
        } else if let data = avatarData {
            self.avatarBase64 = data.base64EncodedString()
        } else {
            self.avatarBase64 = nil
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        if let base64 = try container.decodeIfPresent(String.self, forKey: .avatarBase64) {
            self.avatarBase64 = base64
        } else if let data = try container.decodeIfPresent(Data.self, forKey: .avatarData) {
            self.avatarBase64 = data.base64EncodedString()
        } else {
            self.avatarBase64 = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(avatarBase64, forKey: .avatarBase64)
    }
    
    // Backwards-compatibility helper for any legacy code expecting avatarData
    var avatarData: Data? {
        get {
            guard let base64 = avatarBase64 else { return nil }
            return Data(base64Encoded: base64)
        }
        set {
            avatarBase64 = newValue?.base64EncodedString()
        }
    }
    
    var avatarImage: NSImage? {
        guard let base64 = avatarBase64,
              let data = Data(base64Encoded: base64),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }
    
    static func resizeImageData(_ inputData: Data, targetSize: CGSize = CGSize(width: 32, height: 32)) -> Data? {
        guard let originalImage = NSImage(data: inputData) else { return nil }
        
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        originalImage.draw(in: NSRect(origin: .zero, size: targetSize),
                           from: NSRect(origin: .zero, size: originalImage.size),
                           operation: .copy,
                           fraction: 1.0)
        newImage.unlockFocus()
        
        guard let tiffData = newImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
    
    // Default mock assignees for initial project (가나다 순 정렬)
    static var defaultAssignees: [Assignee] {
        [
            Assignee(name: "김민수"),
            Assignee(name: "박서준"),
            Assignee(name: "이지은"),
            Assignee(name: "정유미"),
            Assignee(name: "최현우")
        ]
    }
    
    /// Returns true if the assignee name consists of English/Latin letters (no Hangul characters)
    var isEnglishName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        // If it contains Korean characters (Hangul syllables or Jamo), it's not English-only
        let hasHangul = trimmed.range(of: "\\p{Hangul}", options: .regularExpression) != nil
        if hasHangul { return false }
        
        // Must contain at least one English/Latin letter
        let hasLatinLetter = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.isASCII }
        return hasLatinLetter
    }
}

import Foundation
import Translation
import SwiftUI

@MainActor
class TranslationService: ObservableObject {
    static let shared = TranslationService()
    
    // In-memory cache to prevent redundant translations
    private var cache: [String: String] = [:]
    
    // Active TranslationSession passed from SwiftUI's .translationTask
    var activeSession: Any? = nil
    
    // Built-in glossary of common project management & development terms
    private let glossary: [String: String] = [
        "기획서 작성 및 요구사항 분석": "Drafting Specification & Requirements Analysis",
        "기획서 작성": "Drafting Specification",
        "기획서": "Specification Document",
        "기획": "Planning",
        "요구사항 분석": "Requirements Analysis",
        "요구사항 정의": "Requirements Definition",
        "요구사항": "Requirements",
        "화면 설계": "UI/UX Screen Design",
        "화면": "Screen / UI",
        "설계": "Design & Architecture",
        "시스템 설계": "System Architecture",
        "DB 설계": "Database Design",
        "데이터베이스": "Database",
        "디자인 시안 제작": "Creating Design Mockups",
        "디자인 시안 검토": "Design Mockup Review",
        "디자인 시안": "Design Mockup",
        "디자인": "Design",
        "시안 제작": "Creating Mockups",
        "시안": "Mockup",
        "프론트엔드 개발": "Frontend Development",
        "프론트엔드": "Frontend",
        "백엔드 개발": "Backend Development",
        "백엔드 API 연동": "Backend API Integration",
        "백엔드": "Backend",
        "API 연동": "API Integration",
        "API 개발": "API Development",
        "서버 구축": "Server Setup",
        "인프라 구축": "Infrastructure Setup",
        "개발": "Development",
        "구현": "Implementation",
        "단위 테스트": "Unit Testing",
        "통합 테스트": "Integration Testing",
        "테스트": "Testing",
        "QA 검수": "QA Verification",
        "QA": "QA",
        "검토 및 승인": "Review & Approval",
        "검토": "Review",
        "승인": "Approval",
        "배포": "Deployment",
        "운영 배포": "Production Deployment",
        "출시": "Release",
        "유지보수": "Maintenance",
        "버그 수정": "Bug Fixing",
        "오류 수정": "Bug Fixing",
        "회의": "Meeting",
        "주간 보고": "Weekly Report",
        "보고": "Reporting",
        "문서화": "Documentation"
    ]
    
    /// Translates a single text from Korean to English.
    /// Uses Apple On-Device TranslationSession if available, otherwise falls back to glossary keyword translation.
    func translate(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        // If text contains no Korean characters, return as-is
        if trimmed.range(of: "\\p{Hangul}", options: .regularExpression) == nil {
            return trimmed
        }
        
        // Check cache
        if let cached = cache[trimmed] {
            return cached
        }
        
        // Check exact glossary match
        if let exact = glossary[trimmed] {
            cache[trimmed] = exact
            return exact
        }
        
        // Attempt Apple Translation Framework if session is available
        if #available(macOS 15.0, *), let session = activeSession as? TranslationSession {
            do {
                let response = try await session.translate(trimmed)
                let result = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !result.isEmpty {
                    cache[trimmed] = result
                    return result
                }
            } catch {
                // If translation session errors out, proceed to glossary fallback
            }
        }
        
        // Fallback: glossary phrase & keyword replacement
        var translated = trimmed
        // Sort keys by descending length to match longest phrases first
        let sortedKeys = glossary.keys.sorted(by: { $0.count > $1.count })
        for key in sortedKeys {
            if translated.contains(key), let val = glossary[key] {
                translated = translated.replacingOccurrences(of: key, with: val)
            }
        }
        
        cache[trimmed] = translated
        return translated
    }
    
    /// Batch translate multiple texts
    func translateBatch(_ texts: [String]) async -> [String: String] {
        var results: [String: String] = [:]
        
        // If Apple TranslationSession is available, attempt batch translations for uncached items
        if #available(macOS 15.0, *), let session = activeSession as? TranslationSession {
            let uncached = texts.filter { str in
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && trimmed.range(of: "\\p{Hangul}", options: .regularExpression) != nil && cache[trimmed] == nil
            }
            if !uncached.isEmpty {
                let requests = uncached.map { TranslationSession.Request(sourceText: $0) }
                if let responses = try? await session.translations(from: requests) {
                    for (orig, resp) in zip(uncached, responses) {
                        let target = resp.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !target.isEmpty {
                            cache[orig] = target
                        }
                    }
                }
            }
        }
        
        for text in texts {
            results[text] = await translate(text)
        }
        return results
    }
}

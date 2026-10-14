import Foundation
import AppKit

class ExcelExporter {
    static func exportTasks(
        assignee: Assignee,
        project: ProjectData,
        exportRows: [ExportTaskRow],
        destinationURL: URL,
        translatedTitles: [UUID: String] = [:],
        translatedNotes: [UUID: String] = [:]
    ) throws {
        let isBilingual = assignee.isEnglishName
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gantt_xlsx_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let relsDir = tempDir.appendingPathComponent("_rels")
        let xlDir = tempDir.appendingPathComponent("xl")
        let xlRelsDir = xlDir.appendingPathComponent("_rels")
        let worksheetsDir = xlDir.appendingPathComponent("worksheets")
        
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worksheetsDir, withIntermediateDirectories: true)
        
        // 1. [Content_Types].xml
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
        try contentTypesXML.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        
        // 2. _rels/.rels
        let rootRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try rootRelsXML.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        
        // 3. xl/_rels/workbook.xml.rels
        let wbRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        try wbRelsXML.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)
        
        // 4. xl/workbook.xml
        let sheetName = isBilingual ? "할일 목록 (To-Do List)" : "할일 목록"
        let workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="\(escapeXML(sheetName))" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
        try workbookXML.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)
        
        // 5. xl/styles.xml
        let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="7">
            <font><sz val="10.5"/><name val="Apple SD Gothic Neo"/></font>
            <font><b/><sz val="16"/><color rgb="FF1E3A8A"/><name val="Apple SD Gothic Neo"/></font>
            <font><sz val="9.5"/><color rgb="FF64748B"/><name val="Apple SD Gothic Neo"/></font>
            <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Apple SD Gothic Neo"/></font>
            <font><b/><sz val="11"/><color rgb="FF0F172A"/><name val="Apple SD Gothic Neo"/></font>
            <font><b/><sz val="10"/><color rgb="FF15803D"/><name val="Apple SD Gothic Neo"/></font>
            <font><b/><sz val="10"/><color rgb="FF1D4ED8"/><name val="Apple SD Gothic Neo"/></font>
          </fonts>
          <fills count="7">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FF2563EB"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFF1F5F9"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFF8FAFC"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFDCFCE7"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFDBEAFE"/></patternFill></fill>
          </fills>
          <borders count="2">
            <border><left/><right/><top/><bottom/><diagonal/></border>
            <border>
              <left style="thin"><color rgb="FFE2E8F0"/></left>
              <right style="thin"><color rgb="FFE2E8F0"/></right>
              <top style="thin"><color rgb="FFE2E8F0"/></top>
              <bottom style="thin"><color rgb="FFE2E8F0"/></bottom>
              <diagonal/>
            </border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="12">
            <!-- 0: Default -->
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <!-- 1: Title Header (16pt Bold Navy) -->
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
            <!-- 2: Subtitle Info (9.5pt Gray) -->
            <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
            <!-- 3: Table Header (11pt Bold White on Blue) -->
            <xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
              <alignment horizontal="center" vertical="center"/>
            </xf>
            <!-- 4: Level 0 Task Title (Bold, Light Gray Fill, Multi-line Wrap) -->
            <xf numFmtId="0" fontId="4" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
              <alignment vertical="top" wrapText="1"/>
            </xf>
            <!-- 5: Normal Task Title (Regular, Indented, Multi-line Wrap) -->
            <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">
              <alignment vertical="top" wrapText="1"/>
            </xf>
            <!-- 6: Multi-line Wrapped Notes -->
            <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">
              <alignment vertical="top" wrapText="1"/>
            </xf>
            <!-- 7: Center Top Normal -->
            <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">
              <alignment horizontal="center" vertical="top"/>
            </xf>
            <!-- 8: Center Top Level 0 -->
            <xf numFmtId="0" fontId="4" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
              <alignment horizontal="center" vertical="top"/>
            </xf>
            <!-- 9: Status Completed (Green Pill) -->
            <xf numFmtId="0" fontId="5" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
              <alignment horizontal="center" vertical="top"/>
            </xf>
            <!-- 10: Status In Progress (Blue Pill) -->
            <xf numFmtId="0" fontId="6" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
              <alignment horizontal="center" vertical="top"/>
            </xf>
            <!-- 11: Level Cell Normal -->
            <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">
              <alignment horizontal="center" vertical="top"/>
            </xf>
          </cellXfs>
        </styleSheet>
        """
        try stylesXML.write(to: xlDir.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)
        
        // 6. xl/worksheets/sheet1.xml
        let today = Date().startOfDay
        let oneMonthLater = Calendar.current.date(byAdding: .month, value: 1, to: today) ?? today.addingDays(30)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.MM.dd"
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "yyyy.MM.dd HH:mm"
        
        let todayStr = dateFormatter.string(from: today)
        let oneMonthStr = dateFormatter.string(from: oneMonthLater)
        let nowStr = dateTimeFormatter.string(from: Date())
        
        var sheetDataXML = ""
        
        // Row 1: Title Banner
        let bannerTitle = isBilingual ? "\(assignee.name) 님 할일 목록 (To-Do List for \(assignee.name))" : "\(assignee.name) 님 할일 목록"
        sheetDataXML += """
            <row r="1" ht="28" customHeight="1">
              <c r="A1" s="1" t="inlineStr"><is><t>\(escapeXML(bannerTitle))</t></is></c>
            </row>
        """
        
        // Row 2: Subtitle Info
        let metaInfo = isBilingual
            ? "프로젝트(Project): \(project.title)  |  대상 기간(Period): \(todayStr) ~ \(oneMonthStr)  |  생성일시(Generated): \(nowStr)  |  총 작업수(Total Tasks): \(exportRows.count)"
            : "프로젝트: \(project.title)  |  대상 기간: \(todayStr) ~ \(oneMonthStr)  |  생성일시: \(nowStr)  |  총 \(exportRows.count)개 작업"
        sheetDataXML += """
            <row r="2" ht="18" customHeight="1">
              <c r="A2" s="2" t="inlineStr"><is><t>\(escapeXML(metaInfo))</t></is></c>
            </row>
        """
        
        // Row 4: Table Headers
        let colAHeader = isBilingual ? "계층 레벨 (Level)" : "계층 레벨"
        let colBHeader = isBilingual ? "작업 이름 (Task Name)" : "작업 이름"
        let colCHeader = isBilingual ? "작업 기간 (Period)" : "작업 기간 (시작일 ~ 종료일)"
        let colDHeader = isBilingual ? "진행 상태 (Status)" : "진행 상태"
        let colEHeader = isBilingual ? "상세 내용 (Details / Notes)" : "상세 내용"
        
        sheetDataXML += """
            <row r="4" ht="26" customHeight="1">
              <c r="A4" s="3" t="inlineStr"><is><t>\(escapeXML(colAHeader))</t></is></c>
              <c r="B4" s="3" t="inlineStr"><is><t>\(escapeXML(colBHeader))</t></is></c>
              <c r="C4" s="3" t="inlineStr"><is><t>\(escapeXML(colCHeader))</t></is></c>
              <c r="D4" s="3" t="inlineStr"><is><t>\(escapeXML(colDHeader))</t></is></c>
              <c r="E4" s="3" t="inlineStr"><is><t>\(escapeXML(colEHeader))</t></is></c>
            </row>
        """
        
        var currentRowNum = 5
        for row in exportRows {
            let task = row.task
            let levelLabel: String
            if isBilingual {
                levelLabel = row.level == 0 ? "상위 작업 (Parent Task)" : "하위 (Subtask Lv.\(row.level))"
            } else {
                levelLabel = row.level == 0 ? "상위 작업" : "하위 (레벨 \(row.level))"
            }
            
            // Task title handling (Bilingual vs Standard)
            let rawTitle = task.title
            let combinedTitle: String
            if isBilingual,
               let enTitle = translatedTitles[task.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !enTitle.isEmpty,
               enTitle.lowercased() != rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                combinedTitle = "\(rawTitle)\n(\(enTitle))"
            } else {
                combinedTitle = rawTitle
            }
            
            // Indented title with branch symbols according to level
            var indentedTitle = ""
            if row.level == 0 {
                indentedTitle = combinedTitle
            } else {
                let branches = String(repeating: "└", count: row.level)
                let lines = combinedTitle.components(separatedBy: "\n")
                if lines.count > 1 {
                    let indentSpaces = String(repeating: " ", count: row.level * 2 + 2)
                    indentedTitle = "\(branches) \(lines[0])\n\(indentSpaces)\(lines[1])"
                } else {
                    indentedTitle = "\(branches) \(combinedTitle)"
                }
            }
            
            // Period
            let startStr = dateFormatter.string(from: task.startDate)
            let endStr = dateFormatter.string(from: task.effectiveEndDate)
            let periodStr = isBilingual
                ? "\(startStr) ~ \(endStr) (\(task.durationDays)일간 / \(task.durationDays) days)"
                : "\(startStr) ~ \(endStr) (\(task.durationDays)일간)"
            
            // Status
            let statusStr: String
            if isBilingual {
                statusStr = task.isCompleted ? "완료 (Completed)" : "진행중 (In Progress)"
            } else {
                statusStr = task.isCompleted ? "완료" : "진행중"
            }
            let statusStyle = task.isCompleted ? 9 : 10
            
            // Notes
            let notesRaw = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let notesDisplay: String
            if notesRaw.isEmpty {
                notesDisplay = "-"
            } else if isBilingual,
                      let enNotes = translatedNotes[task.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !enNotes.isEmpty,
                      enNotes.lowercased() != notesRaw.lowercased() {
                notesDisplay = "\(notesRaw)\n\n[EN] \(enNotes)"
            } else {
                notesDisplay = notesRaw
            }
            
            let titleLines = max(1, indentedTitle.components(separatedBy: "\n").count)
            let notesLines = max(1, notesDisplay.components(separatedBy: "\n").count)
            let maxLines = max(titleLines, notesLines)
            let rowHeight = max(24, 18 + maxLines * 15)
            
            let isLevel0 = row.level == 0
            let titleStyle = isLevel0 ? 4 : 5
            let levelStyle = isLevel0 ? 8 : 11
            let periodStyle = isLevel0 ? 8 : 7
            
            sheetDataXML += """
                <row r="\(currentRowNum)" ht="\(rowHeight)" customHeight="1">
                  <c r="A\(currentRowNum)" s="\(levelStyle)" t="inlineStr"><is><t>\(escapeXML(levelLabel))</t></is></c>
                  <c r="B\(currentRowNum)" s="\(titleStyle)" t="inlineStr"><is><t xml:space="preserve">\(escapeXML(indentedTitle))</t></is></c>
                  <c r="C\(currentRowNum)" s="\(periodStyle)" t="inlineStr"><is><t>\(escapeXML(periodStr))</t></is></c>
                  <c r="D\(currentRowNum)" s="\(statusStyle)" t="inlineStr"><is><t>\(escapeXML(statusStr))</t></is></c>
                  <c r="E\(currentRowNum)" s="6" t="inlineStr"><is><t xml:space="preserve">\(escapeXML(notesDisplay))</t></is></c>
                </row>
            """
            currentRowNum += 1
        }
        
        let sheetXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <cols>
            <col min="1" max="1" width="\(isBilingual ? 22 : 16)" customWidth="1"/>
            <col min="2" max="2" width="\(isBilingual ? 46 : 40)" customWidth="1"/>
            <col min="3" max="3" width="\(isBilingual ? 34 : 28)" customWidth="1"/>
            <col min="4" max="4" width="\(isBilingual ? 18 : 12)" customWidth="1"/>
            <col min="5" max="5" width="\(isBilingual ? 65 : 60)" customWidth="1"/>
          </cols>
          <sheetData>
        \(sheetDataXML)
          </sheetData>
        </worksheet>
        """
        try sheetXML.write(to: worksheetsDir.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)
        
        // 7. Zip into .xlsx using /usr/bin/zip
        let tempZipURL = tempDir.appendingPathComponent("output.xlsx")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.currentDirectoryURL = tempDir
        zipProcess.arguments = ["-r", "-q", tempZipURL.path, "."]
        try zipProcess.run()
        zipProcess.waitUntilExit()
        
        if zipProcess.terminationStatus != 0 {
            throw NSError(domain: "ExcelExporter", code: Int(zipProcess.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "엑셀 파일 생성(ZIP 압축)에 실패했습니다."])
        }
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempZipURL, to: destinationURL)
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    private static func escapeXML(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x26: result.append("&amp;")
            case 0x3C: result.append("&lt;")
            case 0x3E: result.append("&gt;")
            case 0x22: result.append("&quot;")
            case 0x27: result.append("&apos;")
            case 0x0A: result.append("&#10;")
            case 0x0D: result.append("&#13;")
            case 0x09: result.append("&#9;")
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F: break
            default: result.append(String(scalar))
            }
        }
        return result
    }
}

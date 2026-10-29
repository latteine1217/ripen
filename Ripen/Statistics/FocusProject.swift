import Foundation

/// 專注的分類（GLOSSARY）：只是歸屬，以穩定識別碼關聯紀錄，名稱與代表色都不作為身分。
struct FocusProject: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let color: ProjectColor

    init(id: UUID = UUID(), name: String, color: ProjectColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    /// 名稱只去掉前後空白，其餘照使用者輸入保存；空白名稱不是分類。
    static func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 預設色盤中的分類代表色；以原始值保存，色值只在畫面層決定（ADR-0010）。
enum ProjectColor: String, CaseIterable, Sendable {
    case ocean, teal, leaf, amber, tangerine, rose, violet, cocoa

    /// 依色盤順序取第一個還沒用過的顏色；色盤用完就依數量輪替重用。
    static func next(avoiding used: [ProjectColor]) -> ProjectColor {
        allCases.first { !used.contains($0) } ?? allCases[used.count % allCases.count]
    }
}

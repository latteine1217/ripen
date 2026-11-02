import Foundation
import UniformTypeIdentifiers

/// 給試算表讀的原始紀錄（#34）；只能匯出，能匯回 App 的格式只有備份檔。
///
/// 欄名固定英文，作為機器可讀的穩定契約；一筆完成的專注一列，依開始時刻排序。
enum FocusCSV {
    static let contentType = UTType.commaSeparatedText

    static func suggestedFileName(at date: Date) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        return "Ripen Focus Records \(day).csv"
    }

    /// UTF-8 加 BOM，Excel 才會以 UTF-8 開啟中文分類名稱；換行依 RFC 4180 用 CRLF。
    static func data(entries: [StoredFocusRecord], projects: [FocusProject], timeZone: TimeZone) -> Data {
        let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        let utc = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)
        // 預設偏移是 +0800；與其他欄位一致採延伸格式 +08:00
        let local = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true, timeZone: timeZone)
        let header = "id,started_at_utc,started_at_local,duration_seconds,project_id,project_name"
        let rows = entries.sorted { $0.record.startedAt < $1.record.startedAt }.map { entry in
            let record = entry.record
            return [
                entry.id.uuidString,
                record.startedAt.formatted(utc),
                record.startedAt.formatted(local),
                seconds(record.duration),
                record.projectID?.uuidString ?? "",
                // 分類已不存在時保留識別碼、名稱留空，不捏造名稱
                record.projectID.flatMap { names[$0] }.map(field) ?? "",
            ].joined(separator: ",")
        }
        return Data([0xEF, 0xBB, 0xBF]) + Data(([header] + rows).map { $0 + "\r\n" }.joined().utf8)
    }

    /// 保留原始精度：整數秒不帶小數，其餘用 Double 的最短表示。
    private static func seconds(_ value: TimeInterval) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }

    /// 使用者輸入的文字：試算表會把 = + - @ 及 Tab／CR 開頭當成公式，先加單引號；
    /// 含逗號、引號或換行時依 RFC 4180 加引號。
    private static func field(_ text: String) -> String {
        let safe = text.first.map { "=+-@\t\r".contains($0) } == true ? "'" + text : text
        guard safe.contains(where: { ",\"\n\r".contains($0) }) else { return safe }
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

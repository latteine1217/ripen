import Foundation
import Observation
import os

/// 一次完成的專注：統計只需要開始時刻（決定歸屬日期）與長度。
struct FocusRecord: Codable, Equatable, Sendable {
    let startedAt: Date
    let duration: TimeInterval
}

/// 完成的專注要存到哪裡。正式版是本機的 JSON 檔，測試注入記憶體內實作。
protocol FocusLogStorage {
    func load() throws -> [FocusRecord]
    func save(_ records: [FocusRecord]) throws
}

/// 所有完成的專注，依完成順序排列；新增時立即寫入儲存。
@MainActor
@Observable
final class FocusLog {
    private static let logger = Logger(subsystem: "com.latteine.ripen", category: "FocusLog")

    private(set) var records: [FocusRecord]
    /// 為 nil 時只留在記憶體：未注入儲存，或讀取失敗（寫回會蓋掉讀不到的既有紀錄）。
    @ObservationIgnored private let storage: (any FocusLogStorage)?

    init(storage: (any FocusLogStorage)? = nil) {
        do {
            records = try storage?.load() ?? []
            self.storage = storage
        } catch {
            Self.logger.error("讀取專注紀錄失敗，本次執行不寫回：\(error)")
            records = []
            self.storage = nil
        }
    }

    func append(_ record: FocusRecord) {
        records.append(record)
        do {
            try storage?.save(records)
        } catch {
            Self.logger.error("寫入專注紀錄失敗：\(error)")
        }
    }
}

/// 整份紀錄存成一個 JSON 檔；一天幾十筆的量，每次整檔重寫最單純可靠。
struct JSONFileFocusLogStorage: FocusLogStorage {
    let fileURL: URL

    /// ~/Library/Application Support/Ripen/focus-log.json（無 sandbox）
    static let standard = JSONFileFocusLogStorage(
        fileURL: URL.applicationSupportDirectory.appending(path: "Ripen/focus-log.json")
    )

    func load() throws -> [FocusRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return [] }
        return try JSONDecoder().decode([FocusRecord].self, from: Data(contentsOf: fileURL))
    }

    func save(_ records: [FocusRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
    }
}

import Foundation
import SwiftUI

/// 按下後短時間內可以復原的操作。
enum UndoableAction: Equatable, Sendable {
    case skip
    case reset
    case finish

    /// 復原按鈕與選單項目的標題。
    var undoTitle: LocalizedStringKey {
        switch self {
        case .skip: "Undo Skip"
        case .reset: "Undo Reset"
        case .finish: "Undo Done"
        }
    }
}

/// 目前可以復原的操作與期限；期限一過或有其他操作就消失。
struct UndoOffer: Equatable, Sendable {
    let action: UndoableAction
    let expiresAt: Date

    /// 剩下的復原時間占全部的比例（1 → 0），供倒數外圈使用。
    func remainingFraction(at now: Date) -> Double {
        min(max(expiresAt.timeIntervalSince(now) / AppModel.undoWindow, 0), 1)
    }
}

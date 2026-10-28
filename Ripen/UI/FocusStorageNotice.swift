import SwiftUI

/// 計時頁與統計頁共用的錯誤狀態；尚未保存不應看起來像正常保存。
struct FocusStorageNotice: View {
    let log: FocusLog

    var body: some View {
        if let issue = log.issue {
            VStack(alignment: .leading, spacing: 6) {
                Text(issue == .load ? "Focus history could not be loaded." : "Some focuses have not been saved.")
                    .font(.headline)
                Text("Your existing data is kept. You can keep using the timer and retry saving.")
                    .font(.caption)
                if log.pendingCount > 0 {
                    Text("Unsaved focuses: \(log.pendingCount)")
                        .font(.caption)
                }
                Button("Retry", action: log.retry)
            }
            .frame(maxWidth: 300, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityElement(children: .contain)
        }
    }
}

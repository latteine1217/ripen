import SwiftUI

/// 長休息間隔的進度：每完成一次專注填滿一個點。
struct CycleProgressView: View {
    let completed: Int
    let interval: Int

    /// 在設定裡把間隔調到比已完成次數還小時，最多顯示到滿格（下一次專注完成就會進長休息）。
    private var shownCompleted: Int { min(completed, interval) }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<interval, id: \.self) { index in
                Circle()
                    .fill(index < shownCompleted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Long Break Interval"))
        .accessibilityValue(Text("\(shownCompleted) of \(interval) focuses completed"))
        .help(Text("\(shownCompleted) of \(interval) focuses completed"))
    }
}

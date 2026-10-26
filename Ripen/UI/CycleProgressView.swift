import SwiftUI

/// 長休息間隔的進度：每完成一次專注填滿一個點。
struct CycleProgressView: View {
    let completed: Int
    let interval: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<interval, id: \.self) { index in
                Circle()
                    .fill(index < completed ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Long Break Interval"))
        .accessibilityValue(Text("\(completed) of \(interval) focuses completed"))
        .help(Text("\(completed) of \(interval) focuses completed"))
    }
}

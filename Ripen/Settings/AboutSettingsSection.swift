import SwiftUI

/// 設定視窗的「關於」區塊：再看一次手勢介紹。
struct AboutSettingsSection: View {
    let settings: AppSettings
    /// 再看一次手勢介紹時把主視窗叫到前面，介紹就在那裡。
    let showMainWindow: () -> Void

    var body: some View {
        Section {
            LabeledContent("Gesture Guide") {
                Button("Show Again") {
                    settings.replayGestureGuide()
                    showMainWindow()
                }
            }
        } header: {
            Text("About")
        }
    }
}

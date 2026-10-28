import AppKit
import Observation

/// 整個 App 共用系統外觀，讓設定、標題列、系統對話框與 SwiftUI 內容一致。
@MainActor
final class AppAppearanceController {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        applyAndObserve()
    }

    private func applyAndObserve() {
        let mode = withObservationTracking {
            settings.appearanceColorMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.applyAndObserve() }
        }
        NSApplication.shared.appearance = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

import AppKit

/// 以系統音效播放提示音；音效名稱由設定決定（`AppSettings.reminderSoundName`）。
@MainActor
final class SystemReminderSound: ReminderSound {
    func play(named name: String) {
        // NSSound(named:) 回傳共用實例；上一次還在播時 play() 會失敗，先停掉讓新的提醒一定出聲
        guard let sound = NSSound(named: name) else {
            assertionFailure("找不到系統音效 \(name)")
            return
        }
        sound.stop()
        sound.play()
    }
}

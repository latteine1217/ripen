import AppKit
import SwiftUI

/// 同一時間只有一個形態操作有效；拖曳接續過場時保留舞台，其他操作則完整取代它。
@MainActor
final class PresentationTransitions {
    private var current: Operation?

    func begin(continuing operation: Operation? = nil) -> Operation {
        if let operation, current === operation, operation.isActive {
            operation.advance()
            return operation
        }
        current?.cancel()
        let operation = Operation()
        current = operation
        return operation
    }

    func cancel(except operation: Operation? = nil) {
        guard current !== operation else { return }
        current?.cancel()
        current = nil
    }

    /// 把有效性檢查、舞台持有與清理一起封裝；呼叫端不持有序號，也不自行判斷舊回呼。
    @MainActor
    final class Operation {
        private(set) var isActive = true
        private(set) var overlay: TransitionOverlay?
        private var fading: TransitionOverlay?
        private var revision = 0
        private var cleanups: [@MainActor () -> Void] = []
        private var work: Task<Void, Never>?

        fileprivate func advance() {
            revision += 1
            work?.cancel()
            work = nil
        }

        func onEnd(_ cleanup: @escaping @MainActor () -> Void) {
            cleanups.append(cleanup)
        }

        /// 換螢幕時也由同一操作接管新舞台，立即撤掉原舞台。
        func use(_ overlay: TransitionOverlay) {
            self.overlay?.close()
            self.overlay = overlay
        }

        func callback(_ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
            let expected = revision
            return { [weak self] in
                guard let self, self.isActive, self.revision == expected else { return }
                action()
            }
        }

        func animate(_ animation: Animation, changes: () -> Void, completion: @escaping @MainActor () -> Void) {
            withAnimation(animation, completionCriteria: .logicallyComplete, changes, completion: callback(completion))
        }

        func afterFirstFrame(_ action: @escaping @MainActor () -> Void) {
            overlay?.afterFirstFrame(callback(action))
        }

        func play(_ animation: Animation, completion: @escaping @MainActor () -> Void) {
            guard let overlay else { return }
            afterFirstFrame { [weak self] in
                self?.animate(animation, changes: { overlay.progress.t = 1 }, completion: completion)
            }
        }

        func nextTurn(_ action: @escaping @MainActor () -> Void) {
            DispatchQueue.main.async(execute: callback(action))
        }

        func after(_ delay: Duration, _ action: @escaping @MainActor () -> Void) {
            let action = callback(action)
            work?.cancel()
            work = Task {
                do { try await Task.sleep(for: delay) } catch { return }
                action()
            }
        }

        /// 真視窗已接手；淡出中的舞台仍歸操作持有，新操作可立即撤除它。
        func finish(fadeDuration: TimeInterval) {
            fading = overlay
            overlay = nil
            guard let fading else { return cancel() }
            fading.fadeOut(duration: fadeDuration, completion: callback { [weak self] in self?.cancel() })
        }

        func cancel() {
            guard isActive else { return }
            isActive = false
            advance()
            overlay?.close()
            fading?.close()
            overlay = nil
            fading = nil
            let cleanups = cleanups
            self.cleanups = []
            cleanups.forEach { $0() }
        }
    }
}

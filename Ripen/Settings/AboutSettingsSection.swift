import SwiftUI

/// 設定視窗的「關於」區塊：版本、手動檢查更新，以及再看一次手勢介紹。
///
/// 更新只在按下按鈕時連網；有新版時由使用者決定是否下載安裝。
struct AboutSettingsSection: View {
    let settings: AppSettings
    /// 再看一次手勢介紹時把主視窗叫到前面，介紹就在那裡。
    let showMainWindow: () -> Void
    @Environment(UpdateChecker.self) private var updater

    var body: some View {
        Section {
            LabeledContent("Version") {
                Text(verbatim: updater.currentVersion?.description ?? "–")
                    .monospacedDigit()
            }
            LabeledContent {
                Button("Check for Updates…") { Task { await updater.check() } }
                    .disabled(updater.isBusy)
            } label: {
                status
            }
            if case .available(let release) = updater.state {
                LabeledContent {
                    HStack {
                        Link("Release Notes", destination: release.htmlURL)
                        Button("Download and Install") { Task { await updater.downloadAndInstall() } }
                            .buttonStyle(.borderedProminent)
                    }
                } label: {
                    Text("Ripen restarts after installing.")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Gesture Guide") {
                Button("Show Again") {
                    settings.replayGestureGuide()
                    showMainWindow()
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("Ripen only goes online when you check for updates.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .idle:
            Text("Updates")
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
            }
        case .upToDate:
            Text("Ripen is up to date.")
        case .available(let release):
            Text("Ripen \(release.version?.description ?? release.tagName) is available.")
        case .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Downloading…")
            }
        case .restarting:
            Text("Ripen will update when it quits.")
        case .openedDiskImage:
            Text("Drag Ripen from the opened disk image to Applications.")
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 4) {
                Label(message(for: failure), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Link("Open the Download Page", destination: GitHubRelease.releasesPage)
                    .font(.callout)
            }
        }
    }

    private func message(for failure: UpdateChecker.Failure) -> LocalizedStringKey {
        switch failure {
        case .network: "Couldn’t reach GitHub. Check your connection and try again."
        case .cannotVerify: "This release can’t be verified, so it won’t be installed automatically."
        case .verificationFailed: "The download didn’t match the release and was not installed."
        case .installFailed: "Couldn’t install the update."
        }
    }
}

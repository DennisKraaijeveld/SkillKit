import AppKit
import Observation
import Sparkle
import SwiftUI

enum AppUpdatePhase: Equatable {
    case idle
    case checking
    case available(version: String)
    case downloading(version: String)
    case preparing(version: String)
    case ready(version: String)
    case installing(version: String)
    case failed(version: String?, message: String)

    var version: String? {
        switch self {
        case let .available(version),
             let .downloading(version),
             let .preparing(version),
             let .ready(version),
             let .installing(version):
            version
        case let .failed(version, _):
            version
        case .idle, .checking:
            nil
        }
    }

    var title: String {
        switch self {
        case .idle: "Up to date"
        case .checking: "Checking for updates…"
        case let .available(version): "SkillKit \(version) is available"
        case let .downloading(version): "Downloading SkillKit \(version)…"
        case let .preparing(version): "Preparing SkillKit \(version)…"
        case let .ready(version): "SkillKit \(version) is ready"
        case let .installing(version): "Installing SkillKit \(version)…"
        case .failed: "App update failed"
        }
    }

    var detail: String {
        switch self {
        case .idle: "You have the latest version of SkillKit."
        case .checking: "Contacting the SkillKit release feed."
        case .available: "Review the release notes and install when you are ready."
        case .downloading: "The update will be verified before it is installed."
        case .preparing: "The download is being verified and prepared."
        case .ready: "Restart SkillKit to finish installing the update."
        case .installing: "SkillKit will relaunch when installation finishes."
        case let .failed(_, message): message
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "checkmark.circle"
        case .checking: "arrow.clockwise"
        case .available: "arrow.down.circle.fill"
        case .downloading: "arrow.down.circle"
        case .preparing: "shippingbox.circle"
        case .ready: "arrow.clockwise.circle.fill"
        case .installing: "arrow.triangle.2.circlepath.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var showsToolbarItem: Bool {
        switch self {
        case .available, .downloading, .preparing, .ready, .failed:
            true
        case .idle, .checking, .installing:
            false
        }
    }

    var isWorking: Bool {
        switch self {
        case .checking, .downloading, .preparing, .installing:
            true
        default:
            false
        }
    }
}

@Observable
@MainActor
final class ApplicationUpdater: NSObject, SPUUpdaterDelegate {
    private(set) var phase = AppUpdatePhase.idle
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    let isConfigured: Bool

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var immediateInstallHandler: (() -> Void)?

    override init() {
        isConfigured = Self.hasConfiguredReleaseFeed
        super.init()

        guard isConfigured else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        refreshPreferences()
    }

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    var canPerformPrimaryAction: Bool {
        immediateInstallHandler != nil || canCheckForUpdates
    }

    var allowsAutomaticDownloads: Bool {
        updaterController?.updater.allowsAutomaticUpdates ?? false
    }

    var currentVersion: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let marketing, !marketing.isEmpty else { return build ?? "Development" }
        guard let build, !build.isEmpty, build != marketing else { return marketing }
        return "\(marketing) (\(build))"
    }

    var primaryActionTitle: String {
        switch phase {
        case .ready: immediateInstallHandler == nil ? "Show Update" : "Restart to Update"
        case .available, .downloading, .preparing: "Show Update"
        case .failed: "Check Again"
        default: "Check for Updates"
        }
    }

    func performPrimaryAction() {
        if let immediateInstallHandler {
            phase = .installing(version: phase.version ?? "update")
            immediateInstallHandler()
            return
        }
        checkForUpdates()
    }

    func checkForUpdates() {
        guard let updaterController, updaterController.updater.canCheckForUpdates else { return }
        if phase == .idle || isFailure {
            phase = .checking
        }
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        refreshPreferences()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyDownloadsUpdates = enabled
        refreshPreferences()
    }

    func refreshPreferences() {
        guard let updater = updaterController?.updater else { return }
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        immediateInstallHandler = nil
        phase = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        immediateInstallHandler = nil
        phase = .idle
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        phase = .downloading(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        phase = .preparing(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        phase = .failed(version: item.displayVersionString, message: error.localizedDescription)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        if let version = phase.version {
            phase = .available(version: version)
        } else {
            phase = .idle
        }
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        phase = .preparing(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        phase = .ready(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        phase = .installing(version: item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        self.immediateInstallHandler = immediateInstallHandler
        phase = .ready(version: item.displayVersionString)
        return true
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate item: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .skip:
            immediateInstallHandler = nil
            phase = .idle
        case .dismiss:
            switch state.stage {
            case .notDownloaded:
                phase = .available(version: item.displayVersionString)
            case .downloaded, .installing:
                phase = .ready(version: item.displayVersionString)
            @unknown default:
                phase = .available(version: item.displayVersionString)
            }
        case .install:
            if state.stage == .installing {
                phase = .installing(version: item.displayVersionString)
            }
        @unknown default:
            break
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        lastUpdateCheckDate = Date()
        if case .checking = phase {
            phase = error.map {
                .failed(version: nil, message: $0.localizedDescription)
            } ?? .idle
        }
        refreshPreferences()
    }

    private var isFailure: Bool {
        if case .failed = phase { return true }
        return false
    }

    private static var hasConfiguredReleaseFeed: Bool {
        configuredInfoValue("SUFeedURL") != nil && configuredInfoValue("SUPublicEDKey") != nil
    }

    private static func configuredInfoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

struct AppUpdateToolbarControl: View {
    @Environment(ApplicationUpdater.self) private var updater

    var body: some View {
        if updater.phase.isWorking {
            ProgressView()
                .controlSize(.small)
                .help(updater.phase.title)
                .accessibilityLabel(updater.phase.title)
                .accessibilityValue(updater.phase.detail)
        } else {
            Button(action: updater.performPrimaryAction) {
                Label(updater.primaryActionTitle, systemImage: updater.phase.systemImage)
            }
                .labelStyle(.iconOnly)
                .help(updater.phase.title)
                .accessibilityLabel(updater.primaryActionTitle)
                .accessibilityHint(updater.phase.detail)
        }
    }
}

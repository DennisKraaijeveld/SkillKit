import SwiftUI

struct UpdatesSettingsPane: View {
    @Environment(ApplicationUpdater.self) private var updater

    var body: some View {
        Form {
            statusSection
            automaticUpdatesSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SkillbookTheme.surface(.one))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { updater.refreshPreferences() }
    }

    private var statusSection: some View {
        Section {
            updateStatusRow
        } header: {
            Text("SkillKit")
        } footer: {
            Text("App updates are separate from the skill updates shown in the library.")
        }
        .listRowBackground(SkillbookTheme.surface(.three))
    }

    private var automaticUpdatesSection: some View {
        Section {
            Toggle(
                "Automatically check for app updates",
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { enabled in
                        updater.setAutomaticallyChecksForUpdates(enabled)
                    }
                )
            )
            .disabled(!updater.isConfigured)

            Toggle(
                "Automatically download and install app updates",
                isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { enabled in
                        updater.setAutomaticallyDownloadsUpdates(enabled)
                    }
                )
            )
            .disabled(!automaticDownloadsEnabled)
        } header: {
            Text("Automatic updates")
        } footer: {
            Text("Downloaded updates are verified before installation and install when SkillKit restarts or quits.")
        }
        .listRowBackground(SkillbookTheme.surface(.three))
    }

    private var updateStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: statusImage)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.body.weight(.medium))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            updateAction
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var updateAction: some View {
        if updater.phase.isWorking {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(updater.phase.title)
        } else {
            Button(updater.primaryActionTitle) {
                updater.performPrimaryAction()
            }
            .disabled(!updater.isConfigured || !updater.canPerformPrimaryAction)
        }
    }

    private var automaticDownloadsEnabled: Bool {
        updater.isConfigured
            && updater.automaticallyChecksForUpdates
            && updater.allowsAutomaticDownloads
    }

    private var statusTitle: String {
        updater.isConfigured ? updater.phase.title : "App updates unavailable in this build"
    }

    private var statusDetail: String {
        if !updater.isConfigured {
            return "Signed release builds include the update feed and verification key."
        }
        let checked = updater.lastUpdateCheckDate.map {
            " Last checked \($0.formatted(date: .abbreviated, time: .shortened))."
        } ?? ""
        return "Version \(updater.currentVersion). \(updater.phase.detail)\(checked)"
    }

    private var statusImage: String {
        updater.isConfigured ? updater.phase.systemImage : "hammer.circle"
    }

    private var statusColor: Color {
        switch updater.phase {
        case .available, .failed: .orange
        case .ready: .green
        default: .secondary
        }
    }
}

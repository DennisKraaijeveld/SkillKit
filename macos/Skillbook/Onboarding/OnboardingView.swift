import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum OnboardingStep: Int, CaseIterable, Equatable, Identifiable {
    case welcome
    case harnesses
    case folders

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .harnesses: "Agent tools"
        case .folders: "Scan folders"
        }
    }
}

private struct BlurFadeModifier: ViewModifier {
    let opacity: Double
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: radius)
    }
}

private enum OnboardingFolderPurpose: Equatable {
    case work
    case additional
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = OnboardingStep.welcome
    @State private var contentRevealed = false
    @State private var workFolders: [String] = []
    @State private var additionalFolders: [String] = []
    @State private var useDetectedOnly = false
    @State private var pickingFolders = false
    @State private var folderPurpose = OnboardingFolderPurpose.work
    @State private var validationError: String?
    @State private var initialized = false
    @State private var scanDetailsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider()
            ZStack {
                stepContent
                    .id(step)
                    .opacity(contentRevealed ? 1 : 0)
                    .blur(radius: reduceMotion || contentRevealed ? 0 : 10)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 540)
        .background(SkillbookTheme.surface(.one))
        .onAppear {
            initializeDrafts()
            withAnimation(pageAnimation) {
                contentRevealed = true
            }
        }
        .task(id: step) {
            guard step == .harnesses, model.harnesses.isEmpty else { return }
            await model.detectHarnesses()
        }
        .fileImporter(
            isPresented: $pickingFolders,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            handlePickedFolders(result)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases) { item in
                Capsule()
                    .fill(stepBarColor(for: item))
                    .frame(width: 64, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count): \(step.title)")
        .padding(.horizontal, 36)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .harnesses:
            harnessStep
        case .folders:
            foldersStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 30) {
            SkillbookLogo(size: 112)

            VStack(spacing: 12) {
                Text("All your agent skills. One clean library.")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("SkillKit finds the skills your coding tools already use and brings them together in one place.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            HStack(spacing: 22) {
                Label("Scans without changes", systemImage: "checkmark.shield")
                Label("You choose what to scan", systemImage: "folder.badge.plus")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 720)
        .padding(56)
    }

    private var harnessStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.detectingHarnesses ? "Finding agent tools" : harnessHeading)
                        .font(.title.weight(.semibold))
                    Text(model.detectingHarnesses ? checkingSummary : harnessSummary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !model.detectingHarnesses {
                    Button {
                        Task { await model.detectHarnesses() }
                    } label: {
                        Label("Check again", systemImage: "arrow.clockwise")
                    }
                }
            }

            Group {
                if model.detectingHarnesses {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Checking this Mac…")
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if detectedHarnesses.isEmpty {
                    ContentUnavailableView {
                        Label("Choose folders next", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Continue to add a work folder or skill collection.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if sharedHarness != nil || !linkedTools.isEmpty {
                                linkedSkillsOverview
                            }

                            if !standaloneTools.isEmpty || !emptyTools.isEmpty {
                                otherToolsOverview
                            }

                            if model.harnessDetection.brokenLinkCount > 0 {
                                brokenLinksNotice
                            }

                            if hasScanDetails {
                                scanDetails
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .transition(resultTransition)
        }
        .frame(maxWidth: 760)
        .padding(36)
        .animation(resultAnimation, value: model.detectingHarnesses)
    }

    private var linkedSkillsOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let sharedHarness {
                HStack(spacing: 14) {
                    ToolLogo(name: sharedHarness.agent, size: 38)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shared skill library")
                            .font(.headline)
                        Text(countLabel(sharedHarness.sourceSkillCount, singular: "skill"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let path = sharedHarness.skillDirectories.first(where: \.exists)?.path {
                        Text(abbreviatedPath(path))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .padding(18)
            }

            if !linkedTools.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        "Symlinked into \(countLabel(linkedTools.count, singular: "tool"))",
                        systemImage: "link"
                    )
                    .font(.callout.weight(.semibold))

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(linkedTools) { harness in
                            linkedToolChip(harness)
                        }
                    }

                    Text("Each tool uses symlinks to the shared library—no duplicate skill folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
        }
        .skillbookSurface(.two, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func linkedToolChip(_ harness: AgentHarness) -> some View {
        HStack(spacing: 8) {
            ToolLogo(name: harness.agent, size: 24)
                .accessibilityHidden(true)
            Text(harnessTitle(harness.agent))
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(harness.linkedSkillCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(SkillbookTheme.surface(.three), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(harnessTitle(harness.agent)), \(countLabel(harness.linkedSkillCount, singular: "symlinked skill"))"
        )
    }

    private var otherToolsOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not linked to the shared library")
                .font(.headline)

            if !standaloneTools.isEmpty {
                compactToolGroup(
                    title: "Tool-specific skills",
                    detail: "Stored in the tool’s own folder rather than the shared library.",
                    tools: standaloneTools,
                    count: { $0.sourceSkillCount }
                )
            }

            if !emptyTools.isEmpty {
                compactToolGroup(
                    title: "No skill folder found",
                    detail: "SkillKit found the tool, but no skill folder.",
                    tools: emptyTools,
                    count: nil
                )
            }
        }
    }

    private func compactToolGroup(
        title: String,
        detail: String,
        tools: [AgentHarness],
        count: ((AgentHarness) -> UInt32)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(tools) { harness in
                    VStack(spacing: 4) {
                        ToolLogo(name: harness.agent, size: 26)
                        Text(harnessTitle(harness.agent))
                            .font(.caption2)
                            .lineLimit(1)
                        if let count {
                            Text(countLabel(count(harness), singular: "skill"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .skillbookSurface(.two, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var brokenLinksNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("SkillKit skipped \(countLabel(model.harnessDetection.brokenLinkCount, singular: "broken symlink"))")
                    .font(.callout.weight(.semibold))
                Text("Affected tools: \(brokenLinkToolNames). Repair or remove the broken symlinks, then select Check again.")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var foldersStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose where to scan")
                        .font(.title.weight(.semibold))
                    Text("Provider folders are included automatically. Add workspaces or shared skill collections.")
                        .foregroundStyle(.secondary)
                }

                folderSection(
                    title: "Work folders",
                    description: "Folders whose immediate child folders should be available as projects.",
                    paths: workFolders,
                    addLabel: "Add work folders…",
                    purpose: .work
                )

                folderSection(
                    title: "Additional skill folders",
                    description: "Standalone or shared skill collections.",
                    paths: additionalFolders,
                    addLabel: "Add skill folders…",
                    purpose: .additional
                )

                if workFolders.isEmpty && additionalFolders.isEmpty {
                    Toggle(isOn: $useDetectedOnly) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Scan detected folders only")
                                .font(.headline)
                            Text("Start with provider folders. Add more later in Settings.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.checkbox)
                    .padding(16)
                    .skillbookSurface(.two, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let configError = model.config.configError {
                    feedback(configError, systemImage: "exclamationmark.triangle.fill", color: .red)
                }
                if let error = validationError ?? model.onboardingError {
                    feedback(error, systemImage: "exclamationmark.triangle.fill", color: .red)
                }
            }
            .frame(maxWidth: 760)
            .padding(36)
        }
    }

    private var scanDetails: some View {
        DisclosureGroup(isExpanded: $scanDetailsExpanded) {
            VStack(spacing: 0) {
                ForEach(detectedHarnesses) { harness in
                    ForEach(harness.skillDirectories.filter { $0.exists || $0.brokenLinkCount > 0 }) { directory in
                        scanDirectoryRow(harness: harness, directory: directory)
                        if directory.id != visibleSkillDirectories.last?.id { Divider() }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Folder paths and diagnostics", systemImage: "info.circle")
                .font(.callout.weight(.medium))
        }
        .padding(14)
        .skillbookSurface(.two, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func scanDirectoryRow(
        harness: AgentHarness,
        directory: HarnessSkillDirectory
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: directory.linkedSkillCount > 0 ? "link" : "folder")
                .foregroundStyle(directory.brokenLinkCount > 0 ? Color.orange : Color.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(harnessTitle(harness.agent))
                    .font(.callout.weight(.medium))
                Text(directory.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(directoryDetail(directory))
                .font(.caption)
                .foregroundStyle(directory.brokenLinkCount > 0 ? Color.orange : Color.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private func folderSection(
        title: String,
        description: String,
        paths: [String],
        addLabel: String,
        purpose: OnboardingFolderPurpose
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(addLabel) {
                    folderPurpose = purpose
                    pickingFolders = true
                }
            }

            if paths.isEmpty {
                Label("No folders selected", systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(paths, id: \.self) { path in
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(path)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Remove") { remove(path, from: purpose) }
                                .accessibilityLabel("Remove \(URL(fileURLWithPath: path).lastPathComponent)")
                        }
                        .padding(12)
                        if path != paths.last { Divider() }
                    }
                }
                .skillbookSurface(.three, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func feedback(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    let previous = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    navigate(to: previous)
                }
                .disabled(model.savingOnboarding)
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Get started") { navigate(to: .harnesses) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .harnesses:
                Button("Continue") { navigate(to: .folders) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.detectingHarnesses || model.harnesses.isEmpty)
                    .keyboardShortcut(.defaultAction)
            case .folders:
                if model.savingOnboarding {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving setup and scanning skills")
                }
                Button("Finish setup") { finishSetup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.savingOnboarding || model.config.configError != nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
    }

    private var detectedHarnesses: [AgentHarness] {
        model.harnesses.filter(\.detected)
    }

    private var sharedHarness: AgentHarness? {
        detectedHarnesses.first { $0.agent == "agents" }
    }

    private var detectedTools: [AgentHarness] {
        detectedHarnesses.filter { $0.agent != "agents" }
    }

    private var linkedTools: [AgentHarness] {
        detectedTools.filter { $0.linkedSkillCount > 0 }
    }

    private var standaloneTools: [AgentHarness] {
        detectedTools.filter { $0.sourceSkillCount > 0 && $0.linkedSkillCount == 0 }
    }

    private var emptyTools: [AgentHarness] {
        detectedTools.filter {
            $0.sourceSkillCount == 0 && $0.linkedSkillCount == 0 && $0.brokenLinkCount == 0
        }
    }

    private var brokenLinkTools: [AgentHarness] {
        detectedHarnesses.filter { $0.brokenLinkCount > 0 }
    }

    private var visibleSkillDirectories: [HarnessSkillDirectory] {
        detectedHarnesses.flatMap { harness in
            harness.skillDirectories.filter { $0.exists || $0.brokenLinkCount > 0 }
        }
    }

    private var hasScanDetails: Bool {
        !visibleSkillDirectories.isEmpty
    }

    private var harnessHeading: String {
        model.harnessDetection.uniqueSkillCount > 0 ? "Here’s how your skills are organized" : "Agent tools found"
    }

    private var checkingSummary: String {
        "SkillKit checks standard skill folders without changing anything."
    }

    private var harnessSummary: String {
        let skillCount = model.harnessDetection.uniqueSkillCount
        let toolCount = detectedTools.count
        guard skillCount > 0 else {
            return "SkillKit found \(countLabel(toolCount, singular: "tool")). This scan didn’t change any files."
        }
        return "SkillKit found \(countLabel(skillCount, singular: "unique skill")) across \(countLabel(toolCount, singular: "tool")). This scan didn’t change any files."
    }

    private var brokenLinkToolNames: String {
        ListFormatter.localizedString(byJoining: brokenLinkTools.map { harnessTitle($0.agent) })
    }

    private var pageTransition: AnyTransition {
        .modifier(
            active: BlurFadeModifier(opacity: 0, radius: reduceMotion ? 0 : 10),
            identity: BlurFadeModifier(opacity: 1, radius: 0)
        )
    }

    private var resultTransition: AnyTransition {
        .modifier(
            active: BlurFadeModifier(opacity: 0, radius: reduceMotion ? 0 : 6),
            identity: BlurFadeModifier(opacity: 1, radius: 0)
        )
    }

    private var resultAnimation: Animation {
        reduceMotion
            ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
            : .timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    }

    private var pageAnimation: Animation {
        reduceMotion
            ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
            : .timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    }

    private func stepBarColor(for item: OnboardingStep) -> Color {
        if item == step { return .accentColor }
        if item.rawValue < step.rawValue { return Color.accentColor.opacity(0.5) }
        return Color.secondary.opacity(0.18)
    }

    private func navigate(to destination: OnboardingStep) {
        guard destination != step else { return }
        validationError = nil
        model.onboardingError = nil
        withAnimation(pageAnimation) {
            step = destination
        }
    }

    private func initializeDrafts() {
        guard !initialized else { return }
        initialized = true
        workFolders = model.config.projectRoots
        additionalFolders = model.config.customRoots
        useDetectedOnly = false
    }

    private func handlePickedFolders(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var paths: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                paths.append(url.path)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            add(paths, to: folderPurpose)
        case .failure(let error):
            let failure = error as NSError
            guard failure.code != NSUserCancelledError else { return }
            validationError = "Unable to choose folders. \(error.localizedDescription)"
        }
    }

    private func add(_ paths: [String], to purpose: OnboardingFolderPurpose) {
        validationError = nil
        for path in paths.sorted() {
            let otherPaths = purpose == .work ? additionalFolders : workFolders
            if otherPaths.contains(path) {
                validationError = "Choose each folder as either a work folder or an additional skill folder."
                continue
            }
            switch purpose {
            case .work:
                if !workFolders.contains(path) { workFolders.append(path) }
                workFolders.sort()
            case .additional:
                if !additionalFolders.contains(path) { additionalFolders.append(path) }
                additionalFolders.sort()
            }
        }
        if !workFolders.isEmpty || !additionalFolders.isEmpty {
            useDetectedOnly = false
        }
    }

    private func remove(_ path: String, from purpose: OnboardingFolderPurpose) {
        validationError = nil
        switch purpose {
        case .work:
            workFolders.removeAll { $0 == path }
        case .additional:
            additionalFolders.removeAll { $0 == path }
        }
    }

    private func finishSetup() {
        validationError = nil
        if workFolders.isEmpty && additionalFolders.isEmpty && !useDetectedOnly {
            validationError = "Choose a folder, or select “Scan detected folders only.”"
            return
        }
        Task {
            _ = await model.completeOnboarding(
                projectRoots: workFolders,
                customRoots: additionalFolders
            )
        }
    }

    private func harnessTitle(_ agent: String) -> String {
        if agent == "agents" { return "Shared Agent Skills" }
        if let host = SkillHost(agent: agent) { return host.title }
        return agent.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private func directoryDetail(_ directory: HarnessSkillDirectory) -> String {
        var parts: [String] = []
        if directory.sourceSkillCount > 0 {
            parts.append("\(directory.sourceSkillCount) source")
        }
        if directory.linkedSkillCount > 0 {
            parts.append(countLabel(directory.linkedSkillCount, singular: "symlink"))
        }
        if directory.brokenLinkCount > 0 {
            parts.append(countLabel(directory.brokenLinkCount, singular: "broken symlink"))
        }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " · ")
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func countLabel<T: BinaryInteger>(_ count: T, singular: String) -> String {
        "\(count) \(count == 1 ? singular : "\(singular)s")"
    }
}

struct SetupRequiredSettingsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Finish setting up SkillKit", systemImage: "checklist")
        } description: {
            Text("Complete setup in the main window before changing SkillKit settings.")
        }
        .frame(width: 440, height: 220)
        .background(SkillbookTheme.surface(.one))
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel(backend: PreviewBackend(onboardingComplete: false)))
        .frame(width: 820, height: 620)
}

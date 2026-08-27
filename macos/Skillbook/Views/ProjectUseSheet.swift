import SwiftUI

private enum ProjectUseMethod: String, CaseIterable, Identifiable {
    case link = "Link"
    case copy = "Install Copy"

    var id: String { rawValue }
}

struct ProjectUseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var method: ProjectUseMethod = .link
    @State private var projectRoot = ""
    @State private var destinations: Set<ProjectSkillDestination> = [.agents]
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            projectPicker
            methodPicker
            methodDetail
            if let message {
                Label(message, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(failed ? .red : .secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    if model.installing { model.cancelJob() }
                    dismiss()
                }
                Button(actionTitle) {
                    dismiss()
                    Task { await perform() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(actionDisabled)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(SkillbookTheme.surface(.two))
        .onAppear(perform: prepareDefaults)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Use \(skill?.name ?? "skill") in a project")
                .font(.headline)
            Text("Link one shared copy, or install a project-owned copy from its upstream source.")
                .foregroundStyle(.secondary)
        }
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProjectComboBox(
                selection: $projectRoot,
                projects: model.projects,
                recentPaths: model.recentProjectPaths,
                disabled: model.installing,
                onFolderError: { error in
                    message = error
                    failed = true
                }
            )
        }
    }

    private var methodPicker: some View {
        AdaptiveSegmentedPicker(
            "Method",
            selection: $method,
            values: skill?.npxInstall == nil ? [.link] : ProjectUseMethod.allCases,
            optionTitle: \.rawValue
        )
    }

    @ViewBuilder
    private var methodDetail: some View {
        switch method {
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                Text("Edits and updates stay in sync because the project points to this exact skill folder.")
                    .font(.callout)
                LabeledContent("Skill folders") {
                    Menu {
                        ForEach(ProjectSkillDestination.allCases) { destination in
                            Toggle(destination.title, isOn: destinationBinding(destination))
                        }
                    } label: {
                        Text(destinationSummary)
                            .frame(minWidth: 150, alignment: .trailing)
                    }
                }
                pathPreview
            }
        case .copy:
            VStack(alignment: .leading, spacing: 10) {
                Text("Creates a separate project installation with its own files and update lifecycle.")
                    .font(.callout)
                if let source = skill?.sourceLabel, !source.isEmpty {
                    LabeledContent("Source", value: source)
                }
            }
        }
    }

    private var pathPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Creates")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(previewPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var skill: SkillRow? { model.projectUseSkill }

    private var selectedDestinations: [ProjectSkillDestination] {
        ProjectSkillDestination.allCases.filter(destinations.contains)
    }

    private var destinationSummary: String {
        let selected = selectedDestinations
        if selected.isEmpty { return "Choose folders" }
        if selected.count <= 2 { return selected.map(\.title).joined(separator: ", ") }
        return "\(selected[0].title) and \(selected.count - 1) more"
    }

    private var previewPath: String {
        guard let destination = selectedDestinations.first, let skill else { return "No folder selected" }
        let first = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(destination.relativePath)
            .appendingPathComponent(URL(fileURLWithPath: skill.folder).lastPathComponent)
            .path
        return selectedDestinations.count > 1 ? "\(first)  +\(selectedDestinations.count - 1) more" : first
    }

    private var actionTitle: String {
        method == .link ? "Link to Project" : "Install Copy"
    }

    private var actionDisabled: Bool {
        projectRoot.isEmpty
            || model.installing
            || (method == .link && selectedDestinations.isEmpty)
            || (method == .copy && skill?.npxInstall == nil)
    }

    private func destinationBinding(_ destination: ProjectSkillDestination) -> Binding<Bool> {
        Binding(
            get: { destinations.contains(destination) },
            set: { selected in
                if selected {
                    destinations.insert(destination)
                } else {
                    destinations.remove(destination)
                }
            }
        )
    }

    private func prepareDefaults() {
        if projectRoot.isEmpty {
            projectRoot = model.preferredProjectPath
        }
        guard let skill else { return }
        let matching = Set(skill.agents.compactMap(projectDestination))
        if !matching.isEmpty {
            destinations = matching
        }
    }

    private func projectDestination(_ agent: String) -> ProjectSkillDestination? {
        switch agent.lowercased() {
        case "openai": .codex
        case "copilot": .github
        default: ProjectSkillDestination(rawValue: agent.lowercased())
        }
    }

    private func perform() async {
        guard let skill else { return }
        let result: UpdateResult
        switch method {
        case .link:
            result = await model.linkSkill(
                id: skill.id,
                projectRoot: projectRoot,
                destinations: selectedDestinations
            )
        case .copy:
            guard let command = skill.npxInstall else { return }
            result = await model.installSkillInProject(
                spec: command,
                skill: skill.name,
                projectRoot: projectRoot
            )
        }
        if !result.ok {
            model.error = result.message
        }
    }

}

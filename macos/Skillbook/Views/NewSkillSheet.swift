import SwiftUI
import UniformTypeIdentifiers

private enum NewSkillLocation: String, CaseIterable, Identifiable {
    case global = "Global"
    case project = "Project"
    case folder = "Folder"

    var id: String { rawValue }
}

struct NewSkillSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var location = NewSkillLocation.global
    @State private var globalFolders = Set<String>()
    @State private var folder = ""
    @State private var projectRoot = ""
    @State private var picking = false
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New SKILL.md")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: $description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            AdaptiveSegmentedPicker(
                "Create in",
                selection: $location,
                values: NewSkillLocation.allCases,
                optionTitle: \.rawValue
            )
            destinationPicker
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(busy)
                Button {
                    Task { await create() }
                } label: {
                    if busy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Creating…")
                        }
                    } else {
                        Text("Create")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(disabled)
            }
        }
        .padding(20)
        .frame(width: 500)
        .background(SkillbookTheme.surface(.two))
        .onAppear(perform: prepareDefaults)
        .onChange(of: location) { _, location in
            switch location {
            case .global:
                prepareGlobalSelection()
            case .project:
                if projectRoot.isEmpty { projectRoot = model.preferredProjectPath }
            case .folder:
                if !model.customSkillDestinations.contains(where: { $0.path == folder }) {
                    folder = model.customSkillDestinations.first?.path ?? ""
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                _ = url.startAccessingSecurityScopedResource()
                folder = url.path
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private var disabled: Bool {
        let missingDestination = switch location {
        case .global: selectedGlobalDestinations.isEmpty
        case .project: projectRoot.isEmpty
        case .folder: folder.isEmpty
        }
        return busy
            || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || missingDestination
    }

    @ViewBuilder
    private var destinationPicker: some View {
        switch location {
        case .global:
            if model.globalSkillDestinations.isEmpty {
                Label("No global skill folders are available", systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Skill folders") {
                    Menu {
                        ForEach(model.globalSkillDestinations) { destination in
                            Toggle(isOn: globalDestinationBinding(destination.path)) {
                                Label {
                                    Text(globalDestinationTitle(destination))
                                } icon: {
                                    ToolMenuIcon(name: destination.agent)
                                }
                            }
                            .help(destination.path)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if !selectedGlobalDestinations.isEmpty {
                                ToolMenuIconCluster(toolNames: selectedGlobalDestinations.map(\.agent))
                            }
                            Text(globalDestinationSummary)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 210, alignment: .leading)
                    }
                    .accessibilityLabel("Global skill folders")
                    .accessibilityValue(globalDestinationSummary)
                }
                Text("Creates one shared skill and links it to every selected provider folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .project:
            ProjectComboBox(
                selection: $projectRoot,
                projects: model.projects,
                recentPaths: model.recentProjectPaths,
                disabled: busy,
                onFolderError: { model.error = $0 }
            )
            Text("Creates the skill in .agents/skills inside the selected project.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .folder:
            Picker("Skill folder", selection: $folder) {
                Text("Choose a folder…").tag("")
                ForEach(model.customSkillDestinations, id: \.path) { destination in
                    Text(destination.label).tag(destination.path)
                }
                if !folder.isEmpty,
                   !model.customSkillDestinations.contains(where: { $0.path == folder })
                {
                    Text(folder).tag(folder)
                }
            }
            Button("Choose Folder…") { picking = true }
        }
    }

    private var selectedGlobalDestinations: [GlobalDir] {
        model.globalSkillDestinations.filter { globalFolders.contains($0.path) }
    }

    private var globalDestinationSummary: String {
        let titles = selectedGlobalDestinations.map(globalDestinationTitle)
        switch titles.count {
        case 0:
            return "Choose skill folders"
        case 1...2:
            return titles.joined(separator: ", ")
        default:
            return "\(titles[0]) +\(titles.count - 1) more"
        }
    }

    private func globalDestinationTitle(_ destination: GlobalDir) -> String {
        if destination.agent == "agents" { return "Shared Agent Skills" }
        return SkillHost(agent: destination.agent)?.title
            ?? destination.agent.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func globalDestinationBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { globalFolders.contains(path) },
            set: { selected in
                if selected {
                    globalFolders.insert(path)
                } else {
                    globalFolders.remove(path)
                }
            }
        )
    }

    private func prepareDefaults() {
        prepareGlobalSelection()
        if folder.isEmpty {
            folder = model.customSkillDestinations.first?.path ?? ""
        }
        if projectRoot.isEmpty { projectRoot = model.preferredProjectPath }
    }

    private func prepareGlobalSelection() {
        let available = Set(model.globalSkillDestinations.map(\.path))
        globalFolders.formIntersection(available)
        if globalFolders.isEmpty, let first = model.globalSkillDestinations.first {
            globalFolders.insert(first.path)
        }
    }

    private func create() async {
        busy = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = switch location {
        case .global:
            await model.createSkill(
                folders: selectedGlobalDestinations.map(\.path),
                name: trimmedName,
                description: trimmedDescription
            )
        case .project:
            await model.createSkillInProject(
                projectRoot: projectRoot,
                name: trimmedName,
                description: trimmedDescription
            )
        case .folder:
            await model.createSkill(
                folder: folder,
                name: trimmedName,
                description: trimmedDescription
            )
        }
        busy = false
        if ok { dismiss() }
    }
}

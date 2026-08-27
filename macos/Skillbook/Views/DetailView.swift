import SwiftUI

struct DetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(ShortcutSettings.self) private var shortcuts

    var body: some View {
        Group {
            if model.selected != nil {
                switch model.viewMode {
                case .edit:
                    RichMarkdownEditor()
                        .id(model.selectedId)
                case .read:
                    MarkdownPreview()
                        .id(model.selectedId)
                case .source:
                    RawEditorPane()
                        .id(model.selectedId)
                }
            } else if model.scanning && model.skills.isEmpty {
                ProgressView("Scanning skills…")
            } else {
                ContentUnavailableView(
                    "Select a skill",
                    systemImage: "book",
                    description: Text("Pick one from the sidebar, or install a pack.")
                )
            }
        }
        .background(SkillbookTheme.surface(.one))
        .safeAreaInset(edge: .top, spacing: 0) {
            if let skill = model.selected, skill.version == .error {
                SkillCheckErrorNotice(skill: skill)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                @Bindable var model = model
                Menu {
                    ViewModeMenuItems(selection: $model.viewMode, shortcuts: shortcuts)
                } label: {
                    Text(model.viewMode.rawValue)
                }
                .fixedSize()
                .help("Choose how to view this skill")

                Button(action: model.save) {
                    Text("Save")
                }
                .disabled(!model.dirty)
                .keyboardShortcut(shortcuts.shortcut(for: .save).keyboardShortcut)
                .help(model.dirty ? "Save changes" : "No changes to save")

                if let skill = model.selected, skill.canUpdate {
                    Button {
                        model.updateOne(skill.id)
                    } label: {
                        Label("Update", systemImage: "arrow.down.circle")
                    }
                    .disabled(model.updating)
                    .help("Update \(skill.name)")
                }
            }
        }
    }
}

struct SkillLocationsButton: View {
    let skill: SkillRow
    @Environment(AppModel.self) private var model
    @State private var isShowingLocations = false

    var body: some View {
        Button {
            isShowingLocations.toggle()
        } label: {
            Label(locationCountLabel, systemImage: "folder")
                .monospacedDigit()
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("Show \(locationCountLabel) for \(skill.name)")
        .accessibilityLabel("Show \(locationCountLabel) for \(skill.name)")
        .accessibilityValue(isShowingLocations ? "Expanded" : "Collapsed")
        .popover(isPresented: $isShowingLocations, arrowEdge: .bottom) {
            SkillLocationsPopover(skill: skill)
        }
        .onChange(of: model.skillLocationsPresentationRequest) {
            isShowingLocations = true
        }
    }

    private var locationCountLabel: String {
        let count = skill.placements.count
        return count == 1 ? "1 location" : "\(count) locations"
    }
}

private struct SkillLocationsPopover: View {
    let skill: SkillRow
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Skill locations")
                    .font(.headline)
                Text(locationSummary)
                    .font(.callout.weight(.medium))
                Text("Linked locations share edits; installed copies are separate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            if sortedPlacements.isEmpty {
                ContentUnavailableView(
                    "No locations found",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Reload skills to check this location again.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedPlacements, id: \.self) { placement in
                            locationRow(placement)
                            if placement != sortedPlacements.last { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            Divider()

            HStack {
                Button("Open in Finder") { model.revealInFinder(skill) }
                Spacer()
                Button("Use in Project…") {
                    dismiss()
                    model.presentUseInProject(skill.id)
                }
            }
            .padding(12)
        }
        .frame(width: 440)
        .background(SkillbookTheme.surface(.three))
    }

    private var locationSummary: String {
        let sourceCount = skill.placements.count { !$0.isSymlink }
        let linkedCount = skill.placements.count(where: \.isSymlink)
        if sourceCount == 0 && linkedCount == 0 {
            return "No locations found"
        }
        let source = sourceCount == 1 ? "1 source" : "\(sourceCount) sources"
        let linked = linkedCount == 1 ? "1 linked location" : "\(linkedCount) linked locations"
        return "\(source) · \(linked)"
    }

    private var sortedPlacements: [SkillPlacement] {
        skill.placements.sorted {
            if $0.scope != $1.scope { return $0.scope < $1.scope }
            return $0.path < $1.path
        }
    }

    private func locationRow(_ placement: SkillPlacement) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: placement.isSymlink ? "link" : "folder")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(locationTitle(placement))
                        .font(.callout.weight(.medium))
                    Text(placement.isSymlink ? "Linked" : "Source")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(placement.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open in Finder") { model.revealInFinder(skill, path: placement.path) }
                .controlSize(.small)
                .help("Open \(locationTitle(placement)) in Finder")
                .accessibilityLabel("Open in Finder — \(locationTitle(placement))")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func locationTitle(_ placement: SkillPlacement) -> String {
        let agent = if placement.agent == "agents" {
            "Shared"
        } else {
            SkillHost(agent: placement.agent)?.title ?? placement.agent.capitalized
        }
        if let root = placement.root {
            return "\(URL(fileURLWithPath: root).lastPathComponent) · \(agent)"
        }
        return "\(placement.scope.rawValue) · \(agent)"
    }
}

struct ViewModeMenuItems: View {
    @Binding var selection: ViewMode
    let shortcuts: ShortcutSettings

    var body: some View {
        menuItem(.edit)
        menuItem(.read)
        menuItem(.source)
    }

    private func menuItem(_ mode: ViewMode) -> some View {
        Toggle(mode.rawValue, isOn: Binding(
            get: { selection == mode },
            set: { if $0 { selection = mode } }
        ))
        .keyboardShortcut(shortcuts.shortcut(for: mode.shortcutAction).keyboardShortcut)
    }
}

struct SkillCheckErrorNotice: View {
    let skill: SkillRow
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(skill.versionError ?? "Version check failed")
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy") { model.copyVersionError(skill) }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SkillbookTheme.surface(.three))
        .overlay(alignment: .bottom) { Divider() }
    }
}

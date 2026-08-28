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
        let count = model.identicalCopies(of: skill).reduce(0) { $0 + $1.placements.count }
        return count == 1 ? "1 location" : "\(count) locations"
    }
}

private struct SkillLocationItem: Identifiable, Hashable {
    let skill: SkillRow
    let placement: SkillPlacement

    var id: String { "\(skill.id)::\(placement.path)" }
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
                Text(locationExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            if sortedLocations.isEmpty {
                ContentUnavailableView(
                    "No locations found",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Reload skills to check this location again.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedLocations) { location in
                            locationRow(location)
                            if location != sortedLocations.last { Divider() }
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
        let sourceCount = sortedLocations.count { !$0.placement.isSymlink }
        let linkedCount = sortedLocations.count { $0.placement.isSymlink }
        if sourceCount == 0 && linkedCount == 0 {
            return "No locations found"
        }
        let source = sourceCount == 1 ? "1 source" : "\(sourceCount) sources"
        let linked = linkedCount == 1 ? "1 linked location" : "\(linkedCount) linked locations"
        return "\(source) · \(linked)"
    }

    private var locationExplanation: String {
        if identicalCopies.count > 1 {
            return "Independent copies are identical now but are edited separately. Linked locations share edits."
        }
        return "Linked locations share edits; installed copies are separate."
    }

    private var identicalCopies: [SkillRow] {
        model.identicalCopies(of: skill)
    }

    private var sortedLocations: [SkillLocationItem] {
        identicalCopies
            .flatMap { copy in
                copy.placements.map { SkillLocationItem(skill: copy, placement: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.skill.id == model.selectedId, rhs.skill.id != model.selectedId { return true }
                if rhs.skill.id == model.selectedId, lhs.skill.id != model.selectedId { return false }
                if lhs.placement.scope != rhs.placement.scope {
                    return lhs.placement.scope < rhs.placement.scope
                }
                return lhs.placement.path < rhs.placement.path
            }
    }

    private func locationRow(_ location: SkillLocationItem) -> some View {
        let placement = location.placement
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: placement.isSymlink ? "link" : "folder")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(locationTitle(placement))
                        .font(.callout.weight(.medium))
                    Text(locationState(location))
                        .font(.caption2)
                        .foregroundStyle(location.skill.id == model.selectedId && !placement.isSymlink ? .primary : .secondary)
                }
                Text(placement.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !placement.isSymlink, location.skill.id != model.selectedId {
                Button("Edit") {
                    dismiss()
                    model.select(location.skill.id)
                }
                .controlSize(.small)
                .help("Edit this independent copy")
            }
            Button("Open in Finder") { model.revealInFinder(location.skill, path: placement.path) }
                .controlSize(.small)
                .help("Open \(locationTitle(placement)) in Finder")
                .accessibilityLabel("Open in Finder — \(locationTitle(placement))")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func locationState(_ location: SkillLocationItem) -> String {
        if location.placement.isSymlink { return "Linked" }
        return location.skill.id == model.selectedId ? "Editing" : "Copy"
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

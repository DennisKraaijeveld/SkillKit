import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let library = List(selection: Binding(
            get: { model.sidebarSelectedId },
            set: { if let id = $0 { model.selectSidebar(id) } }
        )) {
            ForEach(model.sidebarSections) { section in
                Section("\(section.title) · \(section.skillCount)") {
                    ForEach(section.locations) { location in
                        if location.scope == .global {
                            collections(location.collections)
                        } else {
                            let isExpanded = expansion(
                                id: location.id,
                                containsSelected: location.allSkills.contains {
                                    $0.skill.id == model.selectedId
                                }
                            )
                            DisclosureGroup(
                                isExpanded: isExpanded
                            ) {
                                ForEach(location.skills) { item in
                                    skillRow(item)
                                }
                            } label: {
                                disclosureLabel(isExpanded: isExpanded) {
                                    SidebarLocationHeader(location: location)
                                }
                                .contextMenu {
                                    locationContextMenu(location, isExpanded: isExpanded)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .searchable(
            text: $model.query,
            isPresented: $model.searchPresented,
            placement: .sidebar,
            prompt: "Search skills"
        )
        .overlay {
            if model.scanning && model.skills.isEmpty {
                ProgressView("Scanning skills…")
            } else if model.skills.isEmpty {
                EmptyLibraryView()
            } else if model.filtered.isEmpty && !model.query.isEmpty {
                ContentUnavailableView.search(text: model.query)
            } else if model.filtered.isEmpty && model.outdatedOnly {
                ContentUnavailableView(
                    "No updates available",
                    systemImage: "checkmark.circle",
                    description: Text("Everything in this list is up to date.")
                )
            }
        }

        if #available(macOS 26.0, *) {
            library
                .safeAreaBar(edge: .top, spacing: 0) {
                    sidebarControls
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            library
                .background(SkillbookTheme.surface(.two))
                .safeAreaInset(edge: .top, spacing: 0) {
                    sidebarControls
                        .background(SkillbookTheme.surface(.three))
                        .overlay(alignment: .bottom) { Divider() }
                }
        }
    }

    private var sidebarControls: some View {
        VStack(spacing: 0) {
            sidebarActionRow
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 7)

            Divider()

            HStack {
                Text(resultCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 8)
                Toggle(isOn: Binding(
                    get: { model.outdatedOnly },
                    set: { model.outdatedOnly = $0 }
                )) {
                    Label("Updates only", systemImage: "arrow.down.circle")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show only skills with an available update")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }

    @ViewBuilder
    private var sidebarActionRow: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                actionButtons
            }
        } else {
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            updateButton
            if model.duplicateCopyCount > 0 {
                duplicateButton
            }
        }
    }

    @ViewBuilder
    private var updateButton: some View {
        Group {
            if #available(macOS 26.0, *) {
                if model.availableUpdateCount > 0 {
                    updateButtonLabel
                        .buttonStyle(.glassProminent)
                } else {
                    updateButtonLabel
                        .buttonStyle(.glass)
                }
            } else {
                if model.availableUpdateCount > 0 {
                    updateButtonLabel
                        .buttonStyle(.borderedProminent)
                } else {
                    updateButtonLabel
                        .buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.small)
        .disabled(model.busy)
        .help(primaryUpdateHelp)
    }

    @ViewBuilder
    private var updateButtonLabel: some View {
        if model.availableUpdateCount > 0, !model.checking {
            Menu {
                Button("Check Again", systemImage: "arrow.clockwise", action: model.fetchUpdates)
            } label: {
                updateLabel
            } primaryAction: {
                primaryUpdateAction()
            }
            .accessibilityLabel(primaryUpdateLabel)
            .accessibilityHint(primaryUpdateHelp)
        } else {
            Button(action: primaryUpdateAction) {
                updateLabel
            }
        }
    }

    private var updateLabel: some View {
        HStack(spacing: 6) {
            if model.checking {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: model.availableUpdateCount > 0 ? "arrow.down.circle" : "arrow.clockwise")
            }
            ViewThatFits(in: .horizontal) {
                Text(primaryUpdateLabel)
                Text(compactUpdateLabel)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var duplicateButton: some View {
        if #available(macOS 26.0, *) {
            duplicateButtonLabel
                .buttonStyle(.glass)
        } else {
            duplicateButtonLabel
                .buttonStyle(.bordered)
        }
    }

    private var duplicateButtonLabel: some View {
        Button { model.showDuplicateSheet = true } label: {
            Label {
                ViewThatFits(in: .horizontal) {
                    Text(duplicateLabel)
                    Text("Duplicates")
                }
            } icon: {
                Image(systemName: "square.on.square")
            }
        }
        .controlSize(.small)
        .help(duplicateHelp)
        .accessibilityLabel(duplicateHelp)
    }

    private var resultCountLabel: String {
        if model.filtered.count == model.skills.count {
            return model.skills.count == 1 ? "1 skill" : "\(model.skills.count) skills"
        }
        return "\(model.filtered.count) of \(model.skills.count)"
    }

    private var duplicateHelp: String {
        let count = model.duplicateCopyCount
        return count == 1 ? "Review 1 duplicate copy" : "Review \(count) duplicate copies"
    }

    private var duplicateLabel: String {
        let count = model.duplicateCopyCount
        return count == 1 ? "1 duplicate" : "\(count) duplicates"
    }

    @ViewBuilder
    private func collections(_ groups: [SidebarCollectionGroup]) -> some View {
        ForEach(groups) { collection in
            let isExpanded = expansion(
                id: collection.id,
                containsSelected: containsSelected(collection)
            )
            DisclosureGroup(
                isExpanded: isExpanded
            ) {
                ForEach(collection.skills) { item in
                    skillRow(item)
                }
                ForEach(collection.categories) { category in
                    let categoryExpanded = expansion(
                        id: category.id,
                        containsSelected: category.skills.contains {
                            $0.skill.id == model.selectedId
                        }
                    )
                    DisclosureGroup(
                        isExpanded: categoryExpanded
                    ) {
                        ForEach(category.skills) { item in
                            skillRow(item)
                        }
                    } label: {
                        disclosureLabel(isExpanded: categoryExpanded) {
                            SidebarCategoryHeader(category: category)
                        }
                        .contextMenu {
                            disclosureContextMenu(isExpanded: categoryExpanded)
                        }
                    }
                }
            } label: {
                disclosureLabel(isExpanded: isExpanded) {
                    SidebarCollectionHeader(collection: collection)
                }
                .contextMenu {
                    collectionContextMenu(collection, isExpanded: isExpanded)
                }
            }
        }
    }

    private func disclosureLabel<Label: View>(
        isExpanded: Binding<Bool>,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded.wrappedValue ? "Collapse group" : "Expand group")
    }

    private func skillRow(_ item: SidebarSkillItem) -> some View {
        SkillRowView(
            row: item.skill,
            agents: item.agents,
            linked: item.isLinked,
            placementPath: item.placementPath
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectSidebar(item.id)
        }
        .tag(item.id)
    }

    @ViewBuilder
    private func locationContextMenu(
        _ location: SidebarLocationGroup,
        isExpanded: Binding<Bool>
    ) -> some View {
        if let path = location.path {
            Button("Open in Finder") { model.revealPath(path) }
            Button("Copy Path") { model.copyPath(path) }
            Divider()
        }
        disclosureContextMenu(isExpanded: isExpanded)
    }

    @ViewBuilder
    private func collectionContextMenu(
        _ collection: SidebarCollectionGroup,
        isExpanded: Binding<Bool>
    ) -> some View {
        if let skill = collection.allSkills.first(where: { $0.skill.githubUrl != nil })?.skill {
            Button("Open GitHub") { model.openGitHub(skill) }
            Divider()
        }
        disclosureContextMenu(isExpanded: isExpanded)
    }

    private func disclosureContextMenu(isExpanded: Binding<Bool>) -> some View {
        Button(isExpanded.wrappedValue ? "Collapse" : "Expand") {
            isExpanded.wrappedValue.toggle()
        }
    }

    private func expansion(id: String, containsSelected: Bool) -> Binding<Bool> {
        Binding(
            get: { model.sidebarGroupExpanded(id, containsSelected: containsSelected) },
            set: { model.setSidebarGroupExpanded($0, id: id) }
        )
    }

    private func containsSelected(_ collection: SidebarCollectionGroup) -> Bool {
        collection.skills.contains { $0.skill.id == model.selectedId }
            || collection.categories.contains { category in
                category.skills.contains { $0.skill.id == model.selectedId }
            }
    }

    private var primaryUpdateLabel: String {
        if model.checking { return "Checking GitHub…" }
        let count = model.availableUpdateCount
        return count > 0
            ? "Review \(count) Skill Update\(count == 1 ? "" : "s")"
            : "Check for Skill Updates"
    }

    private var compactUpdateLabel: String {
        if model.checking { return "Checking…" }
        let count = model.availableUpdateCount
        return count > 0 ? "Review \(count)" : "Check Updates"
    }

    private var primaryUpdateHelp: String {
        model.availableUpdateCount > 0
            ? "Review versions and changed files before updating"
            : "Check each source repository for available updates"
    }

    private func primaryUpdateAction() {
        if model.availableUpdateCount > 0 {
            model.reviewFetchedUpdates()
        } else {
            model.fetchUpdates()
        }
    }
}

private struct SidebarLocationHeader: View {
    let location: SidebarLocationGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(location.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(location.skillCount)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .help(location.path ?? location.title)
    }
}

private struct SidebarCollectionHeader: View {
    let collection: SidebarCollectionGroup

    var body: some View {
        HStack(spacing: 6) {
            originMark
                .frame(width: 14, height: 14)
            Text(collection.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if collection.containsLinkedSkill {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Includes linked skills")
            }
            Spacer(minLength: 8)
            if collection.updateCount > 0 {
                Label("\(collection.updateCount)", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                    .help("\(collection.updateCount) updates available")
            } else {
                Text("\(collection.skillCount)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var originMark: some View {
        switch collection.kind {
        case "npx skills":
            Image("LogoSkillsSh")
                .resizable()
                .scaledToFit()
        case "git":
            Image("LogoGitHub")
                .resizable()
                .scaledToFit()
        default:
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SidebarCategoryHeader: View {
    let category: SidebarCategoryGroup

    var body: some View {
        HStack {
            Text(category.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(category.skills.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }
}

struct EmptyLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No skills yet")
                .font(.headline)
            Text("SkillKit looks in the usual agent folders. Choose a project directory or install a pack.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 4) {
                Text("Global folders")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                ForEach(model.config.globalDirs) { dir in
                    HStack {
                        Text(dir.agent)
                        Spacer()
                        Text(dir.exists ? "found" : "missing")
                            .foregroundStyle(dir.exists ? .secondary : .tertiary)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: 240)
            VStack(spacing: 8) {
                Button("Choose work folder…") { model.pickingScanRoot = true }
                Button("Install skill…") { model.showInstallSheet = true }
                Button("New SKILL.md…") { model.showNewSkillSheet = true }
            }
        }
        .padding(20)
    }
}

struct SkillRowView: View {
    @Environment(AppModel.self) private var model
    let row: SkillRow
    let agents: [String]
    let linked: Bool
    let placementPath: String

    init(
        row: SkillRow,
        agents: [String]? = nil,
        linked: Bool = false,
        placementPath: String? = nil
    ) {
        self.row = row
        self.agents = agents ?? row.agents
        self.linked = linked
        self.placementPath = placementPath ?? row.folder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .help(row.name)
                if linked {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Linked to the shared skill")
                        .accessibilityLabel("Linked skill")
                }
                if model.selectedId == row.id && model.dirty {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Unsaved changes")
                }
                Spacer(minLength: 8)
                versionMark
                    .frame(width: 16, height: 16)
            }
            if !row.description.isEmpty {
                Text(row.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(row.description)
            }
            metadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .contextMenu {
            Button("Open in Finder") { model.revealInFinder(row, path: placementPath) }
            Button("Copy Path") { model.copyPath(row, path: placementPath) }
            if row.githubUrl != nil {
                Button("Open GitHub") { model.openGitHub(row) }
            }
            if row.npxInstall != nil {
                Button("Copy skills.sh command") { model.copyNpx(row) }
            }
            Button("Use in Project…") { model.presentUseInProject(row.id) }
            if let message = row.versionError, row.version == .error {
                Button("Copy Error") { model.copyVersionError(row) }
                Button("Show Error") { model.showCheckError(row) }
                    .accessibilityLabel("Show error: \(message)")
            }
            Button("Open in Default App") { model.openInDefaultApp(row) }
            Divider()
            if row.canUpdate {
                Button("Update") { model.updateOne(row.id) }
                    .disabled(model.updating)
            }
            Divider()
            Button("Move to Trash…", role: .destructive) {
                model.requestDelete(row.id)
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if !placementNames.isEmpty || row.modifiedAt != nil {
            HStack(spacing: 7) {
                if !placementNames.isEmpty {
                    ToolLogoCluster(
                        toolNames: placementNames,
                        size: 17,
                        maximumVisible: 3,
                        showsOverflowCount: true
                    )
                }
                if !placementNames.isEmpty, row.modifiedAt != nil {
                    Text("·")
                        .foregroundStyle(.quaternary)
                }
                if let modifiedAt = row.modifiedAt {
                    (Text("Edited ") + Text(modifiedAt, style: .relative))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .monospacedDigit()
                        .help(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var placementNames: [String] {
        var seen = Set<String>()
        return agents.compactMap { name in
            let normalized = name.lowercased()
            guard normalized != "agents", normalized != "local", seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }

    @ViewBuilder
    private var versionMark: some View {
        switch row.version {
        case .updateAvailable:
            Image(systemName: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("Update available")
                .help("Update available")
        case .checking:
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("Checking version")
        case .error:
            let message = row.versionError ?? "Version check failed"
            Button {
                model.showCheckError(row)
            } label: {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Version check failed")
            .help(message)
        default:
            Color.clear
        }
    }
}

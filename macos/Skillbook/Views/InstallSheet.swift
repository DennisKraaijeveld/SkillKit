import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum InstallSheetMode: String, CaseIterable, Identifiable {
    case discover = "Discover"
    case source = "From Source"

    var id: String { rawValue }
}

struct InstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode = InstallSheetMode.discover
    @State private var catalogQuery = ""
    @State private var catalogResults: [SkillsCatalogItem] = []
    @State private var selectedCatalogId: String?
    @State private var catalogError: String?
    @State private var searchingCatalog = false
    @State private var spec = ""
    @State private var skillName = ""
    @State private var global = true
    @State private var message: String?
    @State private var failed = false
    @State private var pickingNpx = false
    @State private var checkingRuntime = false
    @State private var projectRoot = ""
    @FocusState private var catalogSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                AdaptiveSegmentedPicker(
                    "Install from",
                    selection: $mode,
                    values: InstallSheetMode.allCases,
                    role: .tab,
                    showsLabel: false,
                    optionTitle: \.rawValue
                )
                .frame(width: 240)
                .frame(maxWidth: .infinity)

                if !model.npxAvailable {
                    runtimeRequirement
                    Divider()
                }

                Group {
                    switch mode {
                    case .discover:
                        catalogSection
                    case .source:
                        sourceSection
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                installDestination
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 620, height: 570)
        .fileImporter(isPresented: $pickingNpx, allowedContentTypes: [.unixExecutable]) { result in
            chooseNpx(result)
        }
        .task(id: catalogQuery) {
            await searchCatalog()
        }
        .onAppear {
            if projectRoot.isEmpty {
                projectRoot = model.preferredProjectPath
            }
            catalogSearchFocused = true
        }
        .onChange(of: mode) { _, mode in
            message = nil
            failed = false
            if mode == .discover {
                catalogSearchFocused = true
            }
        }
        .onChange(of: selectedCatalogId) { _, _ in
            message = nil
            failed = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Install skill")
                .font(.headline)
            Text("Find a skill on skills.sh or install one directly from a source.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var runtimeRequirement: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("npx is required")
                    .font(.callout.weight(.medium))
                Text(model.npxRequirementMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button("Choose npx…") { pickingNpx = true }
            Button("Check Again") {
                checkingRuntime = true
                Task {
                    _ = await model.refreshRuntime()
                    checkingRuntime = false
                }
            }
            .disabled(checkingRuntime)
            if checkingRuntime {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Search by name or description", text: $catalogQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($catalogSearchFocused)
                    .accessibilityLabel("Search skills.sh")
                if searchingCatalog {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching skills.sh")
                }
            }

            catalogResultsView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let selectedCatalogSkill, let pageURL = selectedCatalogSkill.pageURL {
                HStack(spacing: 8) {
                    Text("\(selectedCatalogSkill.name) · \(selectedCatalogSkill.source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Link(destination: pageURL) {
                        Label("View on skills.sh", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var catalogResultsView: some View {
        let query = trimmedCatalogQuery
        if query.count < 2 {
            catalogPlaceholder(
                title: "Search skills.sh",
                systemImage: "magnifyingglass",
                description: "Enter at least two characters to find skills."
            )
        } else if let catalogError {
            VStack(spacing: 10) {
                catalogPlaceholder(
                    title: "Search unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: catalogError
                )
                Button("Try Again") {
                    Task { await searchCatalog() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchingCatalog && catalogResults.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Searching skills.sh…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if catalogResults.isEmpty {
            catalogPlaceholder(
                title: "No skills found",
                systemImage: "magnifyingglass",
                description: "Try another name, tool, or task."
            )
        } else {
            List(catalogResults, selection: $selectedCatalogId) { skill in
                SkillsCatalogRow(skill: skill, installed: isInstalled(skill))
                    .tag(skill.id)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    private var sourceSection: some View {
        Form {
            Section {
                TextField("Source", text: $spec, prompt: Text("owner/repo, GitHub URL, or npx command"))
                TextField("Skill", text: $skillName, prompt: Text("Optional skill name"))
            } header: {
                Text("Source")
            } footer: {
                Text("Paste an owner/repo, a GitHub URL, or a full npx skills add command.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private var installDestination: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveSegmentedPicker(
                "Install for",
                selection: $global,
                values: [true, false],
                optionTitle: { $0 ? "Global" : "Project" }
            )
            .frame(maxWidth: 320, alignment: .leading)
            if !global {
                projectPicker
            }
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

    private var trimmedCatalogQuery: String {
        catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCatalogSkill: SkillsCatalogItem? {
        guard let selectedCatalogId else { return nil }
        return catalogResults.first { $0.id == selectedCatalogId }
    }

    private var disabled: Bool {
        let missingSource = switch mode {
        case .discover: selectedCatalogSkill == nil
        case .source: spec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return missingSource || !model.npxAvailable || model.installing || (!global && projectRoot.isEmpty)
    }

    private func catalogPlaceholder(
        title: String,
        systemImage: String,
        description: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.installing {
                ProgressView()
                    .controlSize(.small)
                Text(model.progress.label.isEmpty ? "Installing…" : model.progress.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let message {
                Label(message, systemImage: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(failed ? .red : .secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Cancel") {
                if model.installing { model.cancelJob() }
                dismiss()
            }
            Button("Install") {
                Task { await install() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(disabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func searchCatalog() async {
        let query = trimmedCatalogQuery
        guard query.count >= 2 else {
            searchingCatalog = false
            catalogError = nil
            catalogResults = []
            selectedCatalogId = nil
            return
        }

        searchingCatalog = true
        catalogError = nil
        catalogResults = []
        selectedCatalogId = nil

        do {
            try await Task.sleep(for: .milliseconds(250))
            let results = try await SkillsCatalogClient.search(query)
            try Task.checkCancellation()
            guard query == trimmedCatalogQuery else { return }
            catalogResults = results
            selectedCatalogId = results.first?.id
            searchingCatalog = false
        } catch is CancellationError {
            return
        } catch {
            guard query == trimmedCatalogQuery else { return }
            catalogError = error.localizedDescription
            searchingCatalog = false
        }
    }

    private func isInstalled(_ skill: SkillsCatalogItem) -> Bool {
        model.skills.contains { row in
            row.npx
                && row.name.caseInsensitiveCompare(skill.name) == .orderedSame
                && row.sourceLabel.caseInsensitiveCompare(skill.source) == .orderedSame
        }
    }

    private func install() async {
        let installSpec: String
        let installSkill: String?
        switch mode {
        case .discover:
            guard let selectedCatalogSkill else { return }
            installSpec = selectedCatalogSkill.source
            installSkill = selectedCatalogSkill.name
        case .source:
            installSpec = spec
            let skill = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
            installSkill = skill.isEmpty ? nil : skill
        }

        let result = if global {
            await model.installSkill(
                spec: installSpec,
                skill: installSkill,
                global: true
            )
        } else {
            await model.installSkillInProject(
                spec: installSpec,
                skill: installSkill,
                projectRoot: projectRoot
            )
        }
        message = result.message
        failed = !result.ok
        if result.ok {
            dismiss()
        }
    }

    private func chooseNpx(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    _ = try await model.setRuntimeTool(.npx, path: url.path)
                    message = nil
                    failed = false
                } catch {
                    message = error.localizedDescription
                    failed = true
                }
            }
        case .failure(let error):
            let failure = error as NSError
            guard failure.code != NSUserCancelledError else { return }
            message = error.localizedDescription
            failed = true
        }
    }

}

private struct SkillsCatalogRow: View {
    let skill: SkillsCatalogItem
    let installed: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .lineLimit(1)
                Text(skill.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(skill.installCountLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct UpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [VersionChange] = []
    @State private var selected: Set<String> = []
    @State private var focusedId: String?
    @State private var selectedFile: String?
    @State private var outcomes: [String: UpdateResult] = [:]
    @State private var cancelled: Set<String> = []
    @State private var diffCache: [DiffRequest: UpdateFileDiff] = [:]
    @State private var diffErrors: [DiffRequest: String] = [:]
    @State private var applying = false
    @State private var cancelRequested = false
    @State private var pickingNpx = false
    @State private var checkingRuntime = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if unavailableNpxCount > 0 {
                Divider()
                npxRequirement
            }
            Divider()
            HSplitView {
                selectionPane
                    .frame(minWidth: 310, idealWidth: 350)
                detailPane
                    .frame(minWidth: 560, idealWidth: 650)
            }
            Divider()
            footer
        }
        .frame(width: 1_000, height: 660)
        .background(SkillbookTheme.surface(.two))
        .interactiveDismissDisabled(applying)
        .onAppear(perform: prepare)
        .onChange(of: focusedId) { _, _ in selectFirstFile() }
        .task(id: activeDiffRequest) {
            guard let request = activeDiffRequest else { return }
            await loadDiff(request)
        }
        .fileImporter(isPresented: $pickingNpx, allowedContentTypes: [.unixExecutable]) { result in
            chooseNpx(result)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Review updates")
                    .font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(headerSummary(relativeTo: context.date))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if !model.checkWarnings.isEmpty {
                Menu {
                    Section("Check issues") {
                        ForEach(Array(model.checkWarnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                        }
                    }
                } label: {
                    Label(issueLabel, systemImage: "exclamationmark.triangle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Some skills could not be checked. Available updates are still safe to review.")
            }
            if applying || model.updating {
                ProgressView()
                    .controlSize(.small)
                Button(cancelRequested ? "Stopping…" : "Stop") {
                    cancelRequested = true
                    model.cancelJob()
                }
                .disabled(cancelRequested)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var npxRequirement: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(unavailableNpxCount == 1 ? "1 update requires npx" : "\(unavailableNpxCount) updates require npx")
                    .font(.callout.weight(.medium))
                Text(model.npxRequirementMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Choose npx…") { pickingNpx = true }
            Button("Check again") {
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
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Color.red.opacity(0.045))
    }

    private var selectionPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(selected.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Menu("Select") {
                    Button("All") { selected = Set(candidates.filter(isActionable).map(\.skillId)) }
                    Button("Safe only") { selectSafe() }
                    Divider()
                    Button("None") { selected.removeAll() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(applying)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            Divider()
            List(selection: $focusedId) {
                ForEach(sourceGroups) { group in
                    Section(group.source) {
                        ForEach(group.changes) { change in
                            UpdateSelectionRow(
                                change: change,
                                selected: binding(for: change.skillId),
                                outcome: outcomes[change.skillId],
                                cancelled: cancelled.contains(change.skillId),
                                disabled: applying,
                                unavailable: !isActionable(change)
                            )
                            .tag(change.skillId)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(SkillbookTheme.surface(.one))
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let change = focusedChange {
            VStack(spacing: 0) {
                detailHeader(change)
                Divider()
                if change.files.isEmpty {
                    ContentUnavailableView(
                        "No diff available",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("This source did not provide file-level changes.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    fileBar(change)
                    Divider()
                    diffContent
                }
            }
            .background(SkillbookTheme.surface(.two))
        } else {
            ContentUnavailableView(
                "Select an update",
                systemImage: "arrow.left",
                description: Text("Choose a skill to inspect its changes.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ change: VersionChange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.name)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(change.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                DeclaredVersionView(change: change)
            }
            if change.localModified {
                Label("Local edits may be replaced", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if change.requiresNpx, !model.npxAvailable {
                Label("Requires npx", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let outcome = outcomes[change.skillId], !outcome.ok {
                Label(outcome.message, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
    }

    private func fileBar(_ change: VersionChange) -> some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon(selectedFileChange?.kind ?? "modified"))
                .foregroundStyle(fileColor(selectedFileChange?.kind ?? "modified"))
                .accessibilityHidden(true)
            Picker("Changed file", selection: selectedFileBinding(for: change)) {
                ForEach(change.files) { file in
                    Text(file.path).tag(file.path)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 420, alignment: .leading)
            Spacer()
            if let kind = selectedFileChange?.kind {
                Text(kind.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    @ViewBuilder
    private var diffContent: some View {
        if let request = activeDiffRequest {
            if let diff = diffCache[request] {
                UnifiedDiffView(diff: diff)
            } else if let message = diffErrors[request] {
                ContentUnavailableView(
                    "Diff unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading diff…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerStatus
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(applying)
            Button(primaryLabel) {
                Task { await apply() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(actionableIds.isEmpty || applying || model.updating)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    @ViewBuilder
    private var footerStatus: some View {
        if selectedLocalCount > 0 {
            Label(localSelectionMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if failedCount > 0 {
            Label(failureMessage, systemImage: "xmark.circle")
                .foregroundStyle(.red)
        } else if successfulCount > 0, actionableIds.isEmpty {
            Label(successMessage, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        } else {
            Text("Only selected skills will be updated.")
                .foregroundStyle(.secondary)
        }
    }

    private var sourceGroups: [UpdateSourceGroup] {
        Dictionary(grouping: candidates, by: \.source)
            .map { UpdateSourceGroup(source: $0.key, changes: $0.value) }
            .sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
    }

    private var focusedChange: VersionChange? {
        candidates.first { $0.skillId == focusedId }
    }

    private var selectedFileChange: UpdateFileChange? {
        guard let change = focusedChange else { return nil }
        let path = selectedFile.flatMap { selected in
            change.files.contains { $0.path == selected } ? selected : nil
        } ?? change.files.first?.path
        return change.files.first { $0.path == path }
    }

    private var activeDiffRequest: DiffRequest? {
        guard let change = focusedChange, let path = selectedFileChange?.path else { return nil }
        return DiffRequest(skillId: change.skillId, path: path)
    }

    private func headerSummary(relativeTo date: Date) -> String {
        let count = candidates.count
        let available = count == 1 ? "1 update available" : "\(count) updates available"
        guard let checked = model.lastCheckedLabel(relativeTo: date) else { return available }
        return "\(available) · \(checked)"
    }

    private var issueLabel: String {
        model.checkWarnings.count == 1 ? "1 check issue" : "\(model.checkWarnings.count) check issues"
    }

    private var actionableIds: [String] {
        candidates
            .filter(isActionable)
            .map(\.skillId)
            .filter { selected.contains($0) && outcomes[$0]?.ok != true }
    }

    private var unavailableNpxCount: Int {
        guard !model.npxAvailable else { return 0 }
        return candidates.count(where: \.requiresNpx)
    }

    private var selectedLocalCount: Int {
        candidates.filter { selected.contains($0.skillId) && $0.localModified }.count
    }

    private var localSelectionMessage: String {
        selectedLocalCount == 1
            ? "1 selected skill has local edits"
            : "\(selectedLocalCount) selected skills have local edits"
    }

    private var successfulCount: Int { outcomes.values.filter(\.ok).count }
    private var failedCount: Int { outcomes.values.filter { !$0.ok }.count }

    private var successMessage: String {
        successfulCount == 1 ? "1 skill updated" : "\(successfulCount) skills updated"
    }

    private var failureMessage: String {
        failedCount == 1 ? "1 update failed" : "\(failedCount) updates failed"
    }

    private var primaryLabel: String {
        let count = actionableIds.count
        if failedCount > 0, count > 0 {
            return count == 1 ? "Retry Update" : "Retry \(count) Updates"
        }
        return count == 1 ? "Update Skill" : "Update \(count) Skills"
    }

    private func prepare() {
        candidates = model.reviewCandidates
        selected = Set(candidates.filter { !$0.localModified && isActionable($0) }.map(\.skillId))
        focusedId = candidates.first?.skillId
        selectFirstFile()
    }

    private func selectFirstFile() {
        selectedFile = focusedChange?.files.first?.path
    }

    private func selectSafe() {
        selected = Set(candidates.filter { !$0.localModified && isActionable($0) }.map(\.skillId))
    }

    private func isActionable(_ change: VersionChange) -> Bool {
        !change.requiresNpx || model.npxAvailable
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isSelected in
                guard let change = candidates.first(where: { $0.skillId == id }), isActionable(change) else {
                    selected.remove(id)
                    return
                }
                if isSelected {
                    selected.insert(id)
                } else {
                    selected.remove(id)
                }
            }
        )
    }

    private func selectedFileBinding(for change: VersionChange) -> Binding<String> {
        Binding(
            get: {
                selectedFile.flatMap { selected in
                    change.files.contains { $0.path == selected } ? selected : nil
                } ?? change.files.first?.path ?? ""
            },
            set: { selectedFile = $0 }
        )
    }

    private func loadDiff(_ request: DiffRequest) async {
        guard diffCache[request] == nil, diffErrors[request] == nil else { return }
        do {
            let preview = try await model.previewUpdateFile(
                skillId: request.skillId,
                path: request.path
            )
            guard !Task.isCancelled else { return }
            diffCache[request] = preview
        } catch {
            guard !Task.isCancelled else { return }
            diffErrors[request] = error.localizedDescription
        }
    }

    private func apply() async {
        let chosenIds = actionableIds
        guard !chosenIds.isEmpty else { return }
        applying = true
        cancelRequested = false
        cancelled.subtract(chosenIds)
        let results = await model.applySelectedUpdates(chosenIds)
        for result in results {
            outcomes[result.skillId] = result
        }
        let returned = Set(results.map(\.skillId))
        let missing = Set(chosenIds).subtracting(returned)
        if cancelRequested {
            cancelled.formUnion(missing)
        } else {
            for id in missing {
                let name = candidates.first { $0.skillId == id }?.name ?? id
                outcomes[id] = UpdateResult(
                    skillId: id,
                    name: name,
                    ok: false,
                    message: model.error ?? "No result was returned for this skill."
                )
            }
        }
        applying = false
        if !results.isEmpty, results.allSatisfy(\.ok), missing.isEmpty {
            model.flash(successMessage)
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
                    selected.formUnion(candidates.filter { !$0.localModified && isActionable($0) }.map(\.skillId))
                } catch {
                    model.error = error.localizedDescription
                }
            }
        case .failure(let error):
            let failure = error as NSError
            guard failure.code != NSUserCancelledError else { return }
            model.error = error.localizedDescription
        }
    }

    private func fileIcon(_ kind: String) -> String {
        switch kind {
        case "added": "plus.circle.fill"
        case "removed": "minus.circle.fill"
        default: "pencil.circle.fill"
        }
    }

    private func fileColor(_ kind: String) -> Color {
        switch kind {
        case "added": .green
        case "removed": .red
        default: .orange
        }
    }
}

private struct DiffRequest: Hashable {
    var skillId: String
    var path: String
}

private struct UpdateSourceGroup: Identifiable {
    var source: String
    var changes: [VersionChange]
    var id: String { source }
}

private struct UpdateSelectionRow: View {
    let change: VersionChange
    @Binding var selected: Bool
    let outcome: UpdateResult?
    let cancelled: Bool
    let disabled: Bool
    let unavailable: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Toggle("Update \(change.name)", isOn: $selected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(disabled || unavailable || outcome?.ok == true)
                .accessibilityLabel("Update \(change.name)")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(change.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if change.localModified {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Has local edits")
                    }
                }
                if unavailable {
                    Text("Requires npx")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    CompactVersionView(change: change)
                }
            }
            Spacer(minLength: 4)
            if unavailable {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Requires npx")
            } else if let outcome {
                Image(systemName: outcome.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(outcome.ok ? .green : .red)
                    .accessibilityLabel(outcome.ok ? "Updated" : "Update failed")
            } else if cancelled {
                Image(systemName: "stop.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Update stopped")
            }
        }
        .padding(.vertical, 3)
    }
}

private struct CompactVersionView: View {
    let change: VersionChange

    var body: some View {
        if let from = change.from, let to = change.to, from == to {
            Text("\(from) · unchanged")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("Version \(from), unchanged")
        } else if let from = change.from, let to = change.to {
            HStack(spacing: 5) {
                Text(from)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(to)
                    .foregroundStyle(.primary)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Version \(from) to \(to)")
        } else {
            Text("Unversioned")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("This skill does not publish version metadata.")
        }
    }
}

private struct DeclaredVersionView: View {
    let change: VersionChange

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Version")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            CompactVersionView(change: change)
        }
    }
}

private struct UnifiedDiffView: View {
    let diff: UpdateFileDiff

    var body: some View {
        if diff.lines.isEmpty {
            ContentUnavailableView(
                "No textual changes",
                systemImage: "checkmark",
                description: Text("The file contents are identical.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineView(line: line)
                        }
                    }
                    .frame(
                        minWidth: max(680, proxy.size.width),
                        minHeight: proxy.size.height,
                        alignment: .topLeading
                    )
                    .textSelection(.enabled)
                }
                .background(SkillbookTheme.surface(.one))
            }
        }
    }
}

private struct DiffLineView: View {
    let line: UpdateDiffLine

    var body: some View {
        if line.kind == "hunk" {
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.08))
        } else {
            HStack(spacing: 0) {
                lineNumber(line.oldLine)
                lineNumber(line.newLine)
                Text(marker)
                    .foregroundStyle(markerColor)
                    .frame(width: 24)
                Text(line.text.isEmpty ? " " : line.text)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 16)
            }
            .font(.system(size: 12, design: .monospaced))
            .frame(minHeight: 20)
            .background(rowColor)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private func lineNumber(_ number: UInt32?) -> some View {
        Text(number.map(String.init) ?? "")
            .foregroundStyle(.tertiary)
            .frame(width: 42, alignment: .trailing)
            .padding(.trailing, 8)
            .background(Color.primary.opacity(0.025))
    }

    private var marker: String {
        switch line.kind {
        case "added": "+"
        case "removed": "−"
        default: " "
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case "added": .green
        case "removed": .red
        default: .secondary
        }
    }

    private var rowColor: Color {
        switch line.kind {
        case "added": .green.opacity(0.10)
        case "removed": .red.opacity(0.10)
        default: .clear
        }
    }

    private var accessibilityDescription: String {
        let number = line.newLine ?? line.oldLine
        let location = number.map { " line \($0)" } ?? ""
        return "\(line.kind)\(location): \(line.text)"
    }
}

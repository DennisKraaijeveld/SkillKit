import AppKit
import os
import SwiftUI

private enum PendingEditAction {
    case select(String)
    case update(String)
    case reload
    case quit
}

@Observable
@MainActor
final class AppModel {
    var skills: [SkillRow] = [] {
        didSet { rebuildCatalogDerivedState() }
    }
    var selectedId: String?
    var sidebarSelectedId: String?
    var query = "" {
        didSet { rebuildSidebarProjection() }
    }
    var searchPresented = false
    var outdatedOnly = false {
        didSet { rebuildSidebarProjection() }
    }
    var status = "Scanning…"
    var error: String?
    var npxBanner: String?
    var viewMode: ViewMode = .edit
    var yaml = "" {
        didSet { refreshDirtyState() }
    }
    var bodyText = "" {
        didSet { refreshDirtyState() }
    }
    var pendingMarkdownReaderLink: String?
    private(set) var dirty = false
    var markdownReaderOffsets: [String: CGFloat] = [:]
    var yamlOpen = false
    var updateChanges: [VersionChange] = []
    var showUpdateSheet = false
    var reviewingSkillId: String?
    var checkWarnings: [String] = []
    var lastCheckedAt: Date?
    var showInstallSheet = false
    var showNewSkillSheet = false
    var showProjectUseSheet = false
    var showDuplicateSheet = false
    var skillLocationsPresentationRequest = 0
    var projectUseSkillId: String?
    var pickingScanRoot = false
    var scanning = false
    var checking = false {
        didSet { activeJobStateChanged() }
    }
    var updating = false {
        didSet { activeJobStateChanged() }
    }
    var installing = false {
        didSet { activeJobStateChanged() }
    }
    var progress = JobProgress.idle
    var config: ConfigViewModel
    var runtime: RuntimeStatus
    var mcp: McpIntegrationStatus
    private(set) var projects: [ProjectCandidate] = []
    private(set) var recentProjectPaths: [String] = []
    private(set) var harnessDetection = HarnessDetectionSummary.empty
    var detectingHarnesses = false
    var savingOnboarding = false
    var onboardingError: String?
    var appearance: String {
        didSet { SkillbookTheme.applyApplicationAppearance(appearance) }
    }
    var confirmDiscard = false
    var confirmDelete = false
    var pendingDeleteId: String?
    var toast: String?
    private(set) var filtered: [SkillRow] = []
    private(set) var sidebarSections: [SidebarSectionGroup] = []
    private(set) var duplicateGroups: [DuplicateGroup] = []
    private(set) var availableUpdateCount = 0

    private let backend: any SkillbookBackend
    private var pending: PendingEditAction?
    private var pendingSidebarSelectionId: String?
    private var sidebarExpansion: [String: Bool]
    private var editorGeneration: UInt64 = 0
    private var toastToken = UUID()
    private var savedYaml = ""
    private var savedBody = ""
    private var skillIndexById: [String: Int] = [:]
    private var searchTextById: [String: String] = [:]
    private var fullSidebarSections: [SidebarSectionGroup] = []
    private var progressTask: Task<Void, Never>?
    private var updateCancellationRequested = false
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    private static let recentProjectsKey = "recent-project-paths-v1"

    var busy: Bool { scanning || checking || updating || installing }
    var onboardingComplete: Bool { config.onboardingComplete }
    var harnesses: [AgentHarness] { harnessDetection.harnesses }
    var npxAvailable: Bool { runtime.npx.isAvailable }
    var npxRequirementMessage: String {
        "npx is required to install skills. Choose its location or install Node.js, then check again."
    }

    var windowTitle: String {
        guard let name = selected?.name else { return "SkillKit" }
        return dirty ? "\(name) •" : name
    }

    var confirmTitle: String {
        switch pending {
        case .update: "Discard unsaved changes and update?"
        case .quit: "Quit without saving?"
        case .reload: "Reload without saving?"
        default: "Unsaved changes"
        }
    }

    var confirmActionLabel: String {
        switch pending {
        case .update: "Discard and Update"
        default: "Discard"
        }
    }

    var confirmMessage: String {
        switch pending {
        case .update:
            "Unsaved YAML or body edits will be lost. The skill on disk will be replaced."
        case .quit:
            "This skill has unsaved YAML or body edits."
        case .reload:
            "Reload will drop unsaved YAML or body edits."
        default:
            "This skill has unsaved YAML or body edits."
        }
    }

    var confirmShowsSave: Bool {
        switch pending {
        case .update: false
        default: true
        }
    }

    var deleteConfirmName: String {
        skills.first { $0.id == pendingDeleteId }?.name ?? "this skill"
    }

    var selected: SkillRow? {
        selectedId.flatMap { id in skillIndexById[id].map { skills[$0] } }
    }

    var projectUseSkill: SkillRow? {
        projectUseSkillId.flatMap { id in skillIndexById[id].map { skills[$0] } }
    }

    var duplicateCopyCount: Int {
        duplicateGroups.reduce(0) { $0 + max(0, $1.skills.count - 1) }
    }

    var librarySkillCount: Int {
        fullSidebarSections.reduce(0) { $0 + $1.skillCount }
    }

    var visibleSkillCount: Int {
        sidebarSections.reduce(0) { $0 + $1.skillCount }
    }

    func identicalCopies(of skill: SkillRow) -> [SkillRow] {
        guard !skill.exactDuplicateKey.isEmpty else { return [skill] }
        return skills
            .filter { $0.exactDuplicateKey == skill.exactDuplicateKey }
            .sorted { lhs, rhs in
                let lhsSelected = lhs.id == selectedId
                let rhsSelected = rhs.id == selectedId
                if lhsSelected != rhsSelected { return lhsSelected }
                if lhs.scope != rhs.scope { return lhs.scope < rhs.scope }
                return lhs.folder < rhs.folder
            }
    }

    /// Short sidebar copy for the library-wide update review control.
    var updateStatusLabel: String? {
        let n = availableUpdateCount
        guard n > 0 else { return nil }
        let npx = skills.contains { $0.npx && $0.version == .updateAvailable }
        if npx {
            return n == 1 ? "1 npx update" : "\(n) npx updates"
        }
        return n == 1 ? "1 update" : "\(n) updates"
    }

    var reviewCandidates: [VersionChange] {
        guard let reviewingSkillId else { return updateChanges }
        return updateChanges.filter { $0.skillId == reviewingSkillId }
    }

    func lastCheckedLabel(relativeTo date: Date) -> String? {
        guard let lastCheckedAt else { return nil }
        if abs(date.timeIntervalSince(lastCheckedAt)) < 1 {
            return "Checked just now"
        }
        return "Checked \(Self.relativeDateFormatter.localizedString(for: lastCheckedAt, relativeTo: date))"
    }

    var globalSkillDestinations: [GlobalDir] {
        config.globalDirs
            .filter(\.exists)
    }

    var customSkillDestinations: [(label: String, path: String)] {
        config.customRoots.map { ("Custom", $0) }
    }

    var preferredProjectPath: String {
        for path in recentProjectPaths where projects.contains(where: { $0.path == path }) {
            return path
        }
        return projects.count == 1 ? projects[0].path : ""
    }

    init(backend: any SkillbookBackend) {
        self.backend = backend
        var cfg = backend.config()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--restart-onboarding") {
            cfg.onboardingVersion = 0
        }
#endif
        self.config = cfg
        self.runtime = backend.runtimeStatus()
        self.mcp = backend.mcpIntegrationStatus()
        self.appearance = cfg.appearance
        self.sidebarExpansion = UserDefaults.standard.dictionary(forKey: "sidebar-expansion-v1")?
            .compactMapValues { $0 as? Bool } ?? [:]
        self.recentProjectPaths = UserDefaults.standard.stringArray(forKey: Self.recentProjectsKey) ?? []
        SkillbookTheme.applyApplicationAppearance(appearance)
        if cfg.onboardingComplete {
            rescan(silent: false)
        } else {
            status = "Setup required"
        }
    }

    func sidebarGroupExpanded(_ id: String, containsSelected: Bool) -> Bool {
        if !query.isEmpty { return true }
        return sidebarExpansion[id] ?? containsSelected
    }

    func setSidebarGroupExpanded(_ expanded: Bool, id: String) {
        sidebarExpansion[id] = expanded
        UserDefaults.standard.set(sidebarExpansion, forKey: "sidebar-expansion-v1")
    }

    func selectSidebar(_ id: String) {
        guard let item = SidebarTree.item(id: id, in: sidebarSections) else { return }
        if item.contains(skillId: selectedId) {
            sidebarSelectedId = id
            return
        }
        pendingSidebarSelectionId = id
        select(item.skill.id)
        if selectedId == item.skill.id {
            sidebarSelectedId = id
            pendingSidebarSelectionId = nil
        }
    }

    func rescan(silent: Bool) {
        if !silent && dirty {
            pending = .reload
            confirmDiscard = true
            return
        }
        Task { await rescanNow(silent: silent) }
    }

    func select(_ id: String) {
        guard id != selectedId else { return }
        if dirty {
            pending = .select(id)
            confirmDiscard = true
            return
        }
        selectedId = id
        loadSelected(force: false)
    }

    func confirmPending() {
        confirmDiscard = false
        let action = pending
        pending = nil
        markDocumentSaved(yaml: yaml, body: bodyText)
        continuePending(action)
    }

    func saveThenPending() {
        confirmDiscard = false
        let action = pending
        pending = nil
        Task {
            let ok = await saveNow()
            if ok {
                continuePending(action)
            } else if action == .quit {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
    }

    func cancelPending() {
        confirmDiscard = false
        if pending == .quit {
            NSApp.reply(toApplicationShouldTerminate: false)
        }
        pending = nil
        pendingSidebarSelectionId = nil
    }

    func requestQuit() -> Bool {
        if !dirty { return true }
        pending = .quit
        confirmDiscard = true
        return false
    }

    func save() {
        Task { _ = await saveNow() }
    }

    func updateOne(_ id: String) {
        if updating { return }
        if selectedId == id && dirty {
            pending = .update(id)
            confirmDiscard = true
            return
        }
        openUpdateReview(id)
    }

    func fetchUpdates() {
        if busy { return }
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < 30 {
            flash("Updates were checked just now")
            return
        }
        checking = true
        Task {
            defer { checking = false }
            do {
                let snap = try await backend.checkUpdates()
                apply(snap, presentErrors: false)
                lastCheckedAt = Date()
                checkWarnings = snap.errors
                if !snap.versionChanges.isEmpty {
                    updateChanges = snap.versionChanges
                    reviewingSkillId = nil
                    showUpdateSheet = true
                } else if snap.errors.isEmpty {
                    flash("All skills are up to date")
                } else {
                    self.error = snap.errors.first
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func reviewFetchedUpdates() {
        if !updateChanges.isEmpty {
            reviewingSkillId = nil
            showUpdateSheet = true
            return
        }
        fetchUpdates()
    }

    func startSelectedUpdates(_ ids: [String]) {
        guard !ids.isEmpty, !updating else { return }
        showUpdateSheet = false
        Task { _ = await applySelectedUpdates(ids) }
    }

    func applySelectedUpdates(_ ids: [String]) async -> [UpdateResult] {
        guard !ids.isEmpty else { return [] }
        updateCancellationRequested = false
        updating = true
        defer {
            updating = false
            updateCancellationRequested = false
        }
        do {
            let results = try await backend.applyUpdates(ids: ids)
            applyUpdateResults(results)
            if let selectedId, ids.contains(selectedId), !dirty {
                loadSelected(force: true)
            }
            reportUpdateCompletion(results, requestedCount: ids.count)
            return results
        } catch {
            if updateCancellationRequested {
                flash("Update stopped")
            } else {
                self.error = error.localizedDescription
            }
            return []
        }
    }

    func previewUpdateFile(skillId: String, path: String) async throws -> UpdateFileDiff {
        try await backend.previewUpdateFile(skillId: skillId, path: path)
    }

    func retryUpdate(skillId: String) async -> UpdateResult? {
        updating = true
        defer { updating = false }
        do {
            let result = try await backend.updateSkill(id: skillId)
            applyUpdateResults([result])
            if selectedId == skillId {
                loadSelected(force: true)
            }
            return result
        } catch {
            return UpdateResult(skillId: skillId, name: "", ok: false, message: error.localizedDescription)
        }
    }

    func cancelJob() {
        if updating { updateCancellationRequested = true }
        backend.cancelJob()
    }

    func startWatching() async {
        while !Task.isCancelled {
            let changed = await backend.waitForWatchChange()
            guard !Task.isCancelled else { return }
            if !changed {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            while busy && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(160))
            }
            guard !Task.isCancelled else { return }
            await rescanNow(silent: true)
        }
    }

    func applyConfig(_ cfg: ConfigViewModel) {
        config = cfg
        appearance = cfg.appearance
    }

    func detectHarnesses() async {
        guard !detectingHarnesses else { return }
        detectingHarnesses = true
        harnessDetection = await backend.detectHarnesses()
        detectingHarnesses = false
    }

    @discardableResult
    func completeOnboarding(projectRoots: [String], customRoots: [String]) async -> Bool {
        guard !savingOnboarding else { return false }
        savingOnboarding = true
        onboardingError = nil
        defer { savingOnboarding = false }
        do {
            let snapshot = try await backend.completeOnboarding(
                projectRoots: projectRoots,
                customRoots: customRoots
            )
            config = backend.config()
            apply(snapshot)
            await refreshProjects()
            return true
        } catch {
            onboardingError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func refreshRuntime() async -> RuntimeStatus {
        let refreshed = await backend.refreshRuntime()
        runtime = refreshed
        return refreshed
    }

    @discardableResult
    func setRuntimeTool(_ tool: RuntimeTool, path: String?) async throws -> RuntimeStatus {
        let refreshed = try await backend.setRuntimeTool(tool, path: path)
        runtime = refreshed
        config = backend.config()
        await rescanNow(silent: true)
        return refreshed
    }

    func refreshMcpStatus() {
        mcp = backend.mcpIntegrationStatus()
    }

    @discardableResult
    func installMcpServer() async throws -> McpIntegrationStatus {
        let status = try await backend.installMcpServer()
        mcp = status
        return status
    }

    @discardableResult
    func configureMcpClient(_ client: McpClient) async throws -> McpIntegrationStatus {
        let status = try await backend.configureMcpClient(client)
        mcp = status
        return status
    }

    @discardableResult
    func disconnectMcpClient(_ client: McpClient) async throws -> McpIntegrationStatus {
        let status = try await backend.disconnectMcpClient(client)
        mcp = status
        return status
    }

    @discardableResult
    func addProjectRoot(_ path: String) async throws -> String {
        let snapshot = try await backend.addProjectRoot(path)
        apply(snapshot)
        config = backend.config()
        await refreshProjects()
        return snapshot.statusHint
    }

    @discardableResult
    func removeProjectRoot(_ path: String) async throws -> String {
        let snapshot = try await backend.removeProjectRoot(path)
        apply(snapshot)
        config = backend.config()
        await refreshProjects()
        return snapshot.statusHint
    }

    @discardableResult
    func addCustomRoot(_ path: String) async throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return status }
        let snapshot = try await backend.addCustomRoot(trimmed)
        apply(snapshot)
        config = backend.config()
        return snapshot.statusHint
    }

    @discardableResult
    func removeCustomRoot(_ path: String) async throws -> String {
        let snapshot = try await backend.removeCustomRoot(path)
        apply(snapshot)
        config = backend.config()
        return snapshot.statusHint
    }

    func saveAppearance(_ mode: String) async throws {
        guard mode != config.appearance else { return }
        let previous = config.appearance
        appearance = mode
        do {
            applyConfig(try await backend.setAppearance(mode))
        } catch {
            appearance = previous
            throw error
        }
    }

    func installSkill(spec: String, skill: String?, global: Bool) async -> UpdateResult {
        guard npxAvailable else {
            return UpdateResult(
                skillId: skill ?? "install",
                name: skill ?? "install",
                ok: false,
                message: npxRequirementMessage
            )
        }
        installing = true
        defer { installing = false }
        let result = await backend.installSkill(spec: spec, skill: skill, global: global)
        if result.ok {
            flash(result.message)
            await rescanNow(silent: false)
        }
        return result
    }

    func installSkillInProject(
        spec: String,
        skill: String?,
        projectRoot: String
    ) async -> UpdateResult {
        guard npxAvailable else {
            return UpdateResult(
                skillId: skill ?? "install",
                name: skill ?? "install",
                ok: false,
                message: npxRequirementMessage
            )
        }
        installing = true
        defer { installing = false }
        let result = await backend.installSkillInProject(
            spec: spec,
            skill: skill,
            projectRoot: projectRoot
        )
        if result.ok {
            flash(result.message)
            rememberProject(projectRoot)
            await rescanNow(silent: false)
            config = backend.config()
        }
        return result
    }

    func presentUseInProject(_ id: String? = nil) {
        projectUseSkillId = id ?? selectedId
        guard projectUseSkillId != nil else { return }
        showProjectUseSheet = true
    }

    func presentSkillLocations() {
        guard selected != nil else { return }
        skillLocationsPresentationRequest += 1
    }

    func linkSkill(
        id: String,
        projectRoot: String,
        destinations: [ProjectSkillDestination]
    ) async -> UpdateResult {
        installing = true
        defer { installing = false }
        do {
            let result = try await backend.linkSkill(
                id: id,
                projectRoot: projectRoot,
                agents: destinations.map(\.rawValue)
            )
            if result.ok {
                flash(result.message)
                rememberProject(projectRoot)
                await rescanNow(silent: false)
                config = backend.config()
            }
            return result
        } catch {
            return UpdateResult(skillId: id, name: "", ok: false, message: error.localizedDescription)
        }
    }

    func createSkill(folder: String, name: String, description: String) async -> Bool {
        let before = Set(skills.map(\.id))
        do {
            let snap = try await backend.createSkill(folder: folder, name: name, description: description)
            return finishCreating(snap, before: before, name: name)
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func createSkill(folders: [String], name: String, description: String) async -> Bool {
        let before = Set(skills.map(\.id))
        do {
            let snap = try await backend.createSkillInFolders(
                folders: folders,
                name: name,
                description: description
            )
            return finishCreating(snap, before: before, name: name)
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func createSkillInProject(projectRoot: String, name: String, description: String) async -> Bool {
        let before = Set(skills.map(\.id))
        do {
            let snap = try await backend.createSkillInProject(
                projectRoot: projectRoot,
                name: name,
                description: description
            )
            rememberProject(projectRoot)
            await refreshProjects()
            return finishCreating(snap, before: before, name: name)
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func finishCreating(_ snap: Snapshot, before: Set<String>, name: String) -> Bool {
        apply(snap)
        config = backend.config()
        if let created = snap.skills.first(where: { !before.contains($0.id) }) {
            selectedId = created.id
            sidebarSelectedId = SidebarTree.firstItem(
                for: created.id,
                in: SidebarTree.build(skills: skills)
            )?.id
            loadSelected(force: true)
        }
        flash("Created \(name)")
        return true
    }

    private func rememberProject(_ path: String) {
        recentProjectPaths.removeAll { $0 == path }
        recentProjectPaths.insert(path, at: 0)
        recentProjectPaths = Array(recentProjectPaths.prefix(6))
        UserDefaults.standard.set(recentProjectPaths, forKey: Self.recentProjectsKey)
    }

    private func refreshProjects() async {
        projects = await backend.projects()
    }

    func revealPath(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            error = "Location no longer exists. Reload skills and try again.\n\(path)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func revealInFinder(_ row: SkillRow? = nil, path: String? = nil) {
        guard let path = path ?? (row ?? selected)?.folder else { return }
        revealPath(path)
    }

    func copyPath(_ row: SkillRow? = nil, path: String? = nil) {
        guard let path = path ?? (row ?? selected)?.folder else { return }
        copyToPasteboard(path, toast: "Copied path")
    }

    func copyPath(_ path: String) {
        copyToPasteboard(path, toast: "Copied path")
    }

    func copyNpx(_ row: SkillRow? = nil) {
        let command = (row ?? selected)?.npxInstall
        guard let command else { return }
        copyToPasteboard(command, toast: "Copied skills.sh command")
    }

    func copyVersionError(_ row: SkillRow? = nil) {
        let message = (row ?? selected)?.versionError
        guard let message, !message.isEmpty else { return }
        copyToPasteboard(message, toast: "Copied error")
    }

    func showCheckError(_ row: SkillRow) {
        error = row.versionError ?? "Version check failed"
    }

    func openGitHub(_ row: SkillRow? = nil) {
        guard let raw = (row ?? selected)?.githubUrl, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    func openInDefaultApp(_ row: SkillRow? = nil) {
        let path = (row ?? selected)?.skillMd
        guard let path else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func requestDelete(_ id: String? = nil) {
        pendingDeleteId = id ?? selectedId
        guard pendingDeleteId != nil else { return }
        confirmDelete = true
    }

    func cancelDelete() {
        confirmDelete = false
        pendingDeleteId = nil
    }

    func deletePending() {
        confirmDelete = false
        guard let id = pendingDeleteId, let row = skills.first(where: { $0.id == id }) else {
            pendingDeleteId = nil
            return
        }
        pendingDeleteId = nil
        let url = URL(fileURLWithPath: row.folder)
        NSWorkspace.shared.recycle([url]) { _, error in
            Task { @MainActor in
                if let error {
                    self.error = error.localizedDescription
                    return
                }
                if self.selectedId == id {
                    self.selectedId = nil
                    self.sidebarSelectedId = nil
                    self.yaml = ""
                    self.bodyText = ""
                    self.markDocumentSaved(yaml: "", body: "")
                }
                self.flash("Moved to Trash")
                await self.rescanNow(silent: false)
            }
        }
    }

    private func continuePending(_ action: PendingEditAction?) {
        switch action {
        case let .select(id):
            selectedId = id
            sidebarSelectedId = pendingSidebarSelectionId
                ?? SidebarTree.firstItem(for: id, in: sidebarSections)?.id
            pendingSidebarSelectionId = nil
            loadSelected(force: true)
        case let .update(id):
            loadSelected(force: true)
            openUpdateReview(id)
        case .reload:
            Task { await rescanNow(silent: false) }
        case .quit:
            NSApp.reply(toApplicationShouldTerminate: true)
        case nil:
            break
        }
    }

    private func saveNow() async -> Bool {
        guard let id = selectedId, dirty else { return true }
        if let issue = Self.frontmatterIssue(yaml) {
            error = issue
            yamlOpen = true
            viewMode = viewMode == .read ? .source : viewMode
            return false
        }
        let yaml = self.yaml
        let body = bodyText
        let generation = editorGeneration
        do {
            try await backend.saveSkill(id: id, yaml: yaml, body: body)
            guard selectedId == id, editorGeneration == generation else { return true }
            markDocumentSaved(yaml: yaml, body: body)
            error = nil
            flash("Saved")
            return true
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func openUpdateReview(_ id: String) {
        guard updateChanges.contains(where: { $0.skillId == id }) else {
            fetchUpdates()
            return
        }
        reviewingSkillId = id
        showUpdateSheet = true
    }

    private func applyUpdateResults(_ results: [UpdateResult]) {
        let succeeded = Set(results.filter(\.ok).map(\.skillId))
        guard !succeeded.isEmpty else { return }
        var updatedSkills = skills
        for index in updatedSkills.indices where succeeded.contains(updatedSkills[index].id) {
            updatedSkills[index].version = .upToDate
            updatedSkills[index].bumpFrom = nil
            updatedSkills[index].bumpTo = nil
        }
        skills = updatedSkills
        updateChanges.removeAll { succeeded.contains($0.skillId) }
    }

    private func reportUpdateCompletion(_ results: [UpdateResult], requestedCount: Int) {
        let successfulCount = results.count(where: \.ok)
        if updateCancellationRequested {
            let suffix = successfulCount > 0 ? " · \(successfulCount) updated" : ""
            flash("Update stopped\(suffix)")
            return
        }
        let failures = results.filter { !$0.ok }
        if let firstFailure = failures.first {
            self.error = failures.count == 1
                ? firstFailure.message
                : "\(failures.count) updates failed. \(firstFailure.message)"
            return
        }
        guard results.count == requestedCount else {
            self.error = "The update ended before every selected skill returned a result."
            return
        }
        flash(successfulCount == 1 ? "1 skill updated" : "\(successfulCount) skills updated")
    }

    /// Disk scan only. Remote checks run explicitly, not on launch or reload.
    private func rescanNow(silent: Bool) async {
        if scanning { return }
        if silent && (checking || updating || installing) { return }
        let signposter = SkillbookSignposts.operations
        let signpostState = signposter.beginInterval("Catalog Scan")
        defer { signposter.endInterval("Catalog Scan", signpostState) }
        scanning = true
        do {
            let snap = try await backend.scan(silent: silent)
            apply(snap, silent: silent)
            await refreshProjects()
        } catch {
            self.error = error.localizedDescription
        }
        scanning = false
    }

    private func loadSelected(force: Bool) {
        editorGeneration += 1
        let generation = editorGeneration
        guard let id = selectedId else {
            yaml = ""
            bodyText = ""
            markDocumentSaved(yaml: "", body: "")
            return
        }
        Task {
            do {
                let parsed = try await backend.readSkill(id: id)
                guard editorGeneration == generation, selectedId == id else { return }
                if !force && dirty { return }
                yaml = parsed.yaml
                bodyText = parsed.body
                yamlOpen = false
                markDocumentSaved(yaml: parsed.yaml, body: parsed.body)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Silent rescans keep the open editor and do not clear a banner the user has not dismissed.
    private func apply(_ snap: Snapshot, silent: Bool = false, presentErrors: Bool = true) {
        if skills != snap.skills { skills = snap.skills }
        if presentErrors, !silent || !snap.errors.isEmpty {
            let nextError = snap.errors.first
            if error != nextError { error = nextError }
        }
        if status != snap.statusHint { status = snap.statusHint }
        if npxBanner != snap.npxBanner { npxBanner = snap.npxBanner }
        if updateChanges != snap.versionChanges { updateChanges = snap.versionChanges }
        let fullSidebar = fullSidebarSections
        let stillThere = skills.contains { $0.id == selectedId }
        if selectedId == nil {
            selectedId = skills.first?.id
            if let selectedId {
                sidebarSelectedId = SidebarTree.firstItem(for: selectedId, in: fullSidebar)?.id
            }
            loadSelected(force: false)
        } else if !stillThere {
            if dirty { return }
            selectedId = skills.first?.id
            if let selectedId {
                sidebarSelectedId = SidebarTree.firstItem(for: selectedId, in: fullSidebar)?.id
            }
            loadSelected(force: false)
        } else if let sidebarSelectedId,
                  SidebarTree.item(id: sidebarSelectedId, in: fullSidebar)?.contains(skillId: selectedId) != true
        {
            self.sidebarSelectedId = selectedId.flatMap {
                SidebarTree.firstItem(for: $0, in: fullSidebar)?.id
            }
        } else if sidebarSelectedId == nil, let selectedId {
            sidebarSelectedId = SidebarTree.firstItem(
                for: selectedId,
                in: fullSidebar
            )?.id
        }
    }

    private func rebuildCatalogDerivedState() {
        skillIndexById.removeAll(keepingCapacity: true)
        searchTextById.removeAll(keepingCapacity: true)
        for (index, skill) in skills.enumerated() {
            skillIndexById[skill.id] = index
            searchTextById[skill.id] = Self.searchableText(for: skill)
        }
        duplicateGroups = Dictionary(grouping: skills, by: \.duplicateKey)
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map { key, copies in
                DuplicateGroup(
                    id: key,
                    reason: copies[0].duplicateReason,
                    skills: copies.sorted { $0.folder < $1.folder }
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        availableUpdateCount = skills.count { $0.version == .updateAvailable }
        fullSidebarSections = SidebarTree.build(skills: skills)
        rebuildSidebarProjection()
    }

    private func rebuildSidebarProjection() {
        let signposter = SkillbookSignposts.rendering
        let signpostState = signposter.beginInterval("Sidebar Projection")
        defer { signposter.endInterval("Sidebar Projection", signpostState) }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedQuery.isEmpty && !outdatedOnly {
            filtered = skills
            sidebarSections = fullSidebarSections
            return
        }
        filtered = skills.filter { skill in
            if outdatedOnly && skill.version != .updateAvailable { return false }
            return normalizedQuery.isEmpty
                || searchTextById[skill.id]?.contains(normalizedQuery) == true
        }
        sidebarSections = SidebarTree.build(skills: filtered)
    }

    private static func searchableText(for skill: SkillRow) -> String {
        var fields = [
            skill.name,
            skill.description,
            skill.sourceLabel,
            skill.collectionLabel,
            skill.sourceCategory ?? "",
            skill.path,
            skill.folder,
        ]
        fields.append(contentsOf: skill.agents)
        for placement in skill.placements {
            fields.append(placement.path)
            if let root = placement.root { fields.append(root) }
        }
        if skill.npx { fields.append("npx skills skills.sh") }
        return fields.joined(separator: "\n").lowercased()
    }

    private func refreshDirtyState() {
        dirty = yaml != savedYaml || bodyText != savedBody
    }

    private func markDocumentSaved(yaml: String, body: String) {
        savedYaml = yaml
        savedBody = body
        refreshDirtyState()
    }

    private func activeJobStateChanged() {
        let hasActiveJob = checking || updating || installing
        guard hasActiveJob else {
            progressTask?.cancel()
            progressTask = nil
            progress = .idle
            return
        }
        guard progressTask == nil else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.checking || self.updating || self.installing else { return }
                let next = self.backend.progress()
                if self.progress != next { self.progress = next }
                do {
                    try await Task.sleep(for: .milliseconds(160))
                } catch {
                    return
                }
            }
        }
    }

    private func copyToPasteboard(_ string: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        flash(toast)
    }

    func flash(_ message: String) {
        toast = message
        let token = UUID()
        toastToken = token
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toastToken == token { toast = nil }
        }
    }

    static func frontmatterIssue(_ yaml: String) -> String? {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "SKILL.md needs YAML frontmatter with name and description"
        }
        var name: String?
        var description: String?
        for raw in trimmed.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if name == nil, let value = yamlScalar(line, key: "name") { name = value }
            if description == nil, let value = yamlScalar(line, key: "description") { description = value }
        }
        if name == nil { return "YAML needs a name" }
        if description == nil { return "YAML needs a description" }
        return nil
    }

    private static func yamlScalar(_ line: String, key: String) -> String? {
        let prefix = "\(key):"
        guard line.hasPrefix(prefix) else { return nil }
        var value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2)
            || (value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2)
        {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }

    private static func composed(yaml: String, body: String) -> String {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return body }
        return "---\n\(trimmed)\n---\n\n\(body.trimmingCharacters(in: .newlines))\n"
    }
}

extension PendingEditAction: Equatable {}

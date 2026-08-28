import Foundation

private struct DisplayedError: LocalizedError {
    let errorDescription: String?
}

extension SkillbookError {
    var message: String {
        switch self {
        case let .Message(message):
            return message
        }
    }
}

extension SkillScope {
    init(_ scope: FfiScope) {
        switch scope {
        case .global: self = .global
        case .project: self = .project
        case .custom: self = .custom
        }
    }
}

extension SkillVersion {
    init(_ version: FfiVersion) {
        switch version {
        case .unknown: self = .unknown
        case .checking: self = .checking
        case .upToDate: self = .upToDate
        case .updateAvailable: self = .updateAvailable
        case .untracked: self = .untracked
        case .error: self = .error
        }
    }
}

extension SkillPlacement {
    init(_ placement: FfiSkillPlacement) {
        self.init(
            agent: placement.agent,
            path: placement.path,
            scope: SkillScope(placement.scope),
            root: placement.root,
            isSymlink: placement.isSymlink
        )
    }
}

extension SkillRow {
    init(_ row: FfiSkillRow) {
        self.init(
            id: row.id,
            name: row.name,
            description: row.description,
            scope: SkillScope(row.scope),
            agents: row.agents,
            path: row.path,
            npx: row.npx,
            sourceLabel: row.sourceLabel,
            sourceKind: row.sourceKind,
            collectionId: row.collectionId,
            collectionLabel: row.collectionLabel,
            sourceCategory: row.sourceCategory,
            placements: row.placements.map(SkillPlacement.init),
            duplicateKey: row.duplicateKey,
            exactDuplicateKey: row.exactDuplicateKey,
            duplicateReason: row.duplicateReason,
            version: SkillVersion(row.version),
            bumpFrom: row.bumpFrom,
            bumpTo: row.bumpTo,
            folder: row.folder,
            skillMd: row.skillMd,
            githubUrl: row.githubUrl,
            npxInstall: row.npxInstall,
            versionError: row.versionError,
            modifiedAt: row.modifiedAtUnixSeconds.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
        )
    }
}

extension VersionChange {
    init(_ row: FfiVersionChange) {
        self.init(
            skillId: row.skillId,
            name: row.name,
            from: row.from,
            to: row.to,
            source: row.source,
            requiresNpx: row.requiresNpx,
            localModified: row.localModified,
            files: row.files.map(UpdateFileChange.init)
        )
    }
}

extension UpdateFileChange {
    init(_ row: FfiUpdateFileChange) {
        self.init(path: row.path, kind: row.kind)
    }
}

extension UpdateFileDiff {
    init(_ row: FfiUpdateFileDiff) {
        self.init(path: row.path, lines: row.lines.map(UpdateDiffLine.init))
    }
}

extension UpdateDiffLine {
    init(_ row: FfiUpdateDiffLine) {
        self.init(kind: row.kind, oldLine: row.oldLine, newLine: row.newLine, text: row.text)
    }
}

extension Snapshot {
    init(_ snap: FfiSnapshot) {
        self.init(
            skills: snap.skills.map(SkillRow.init),
            errors: snap.errors,
            statusHint: snap.statusHint,
            npxBanner: snap.npxBanner,
            versionChanges: snap.versionChanges.map(VersionChange.init),
            scanning: snap.scanning
        )
    }
}

extension ParsedSkillFile {
    init(_ parsed: FfiParsedSkill) {
        self.init(yaml: parsed.yaml, body: parsed.body, name: parsed.name, description: parsed.description)
    }
}

extension GlobalDir {
    init(_ row: FfiGlobalDir) {
        self.init(agent: row.agent, path: row.path, exists: row.exists)
    }
}

extension ProjectCandidate {
    init(_ row: FfiProjectCandidate) {
        self.init(name: row.name, path: row.path, workRoot: row.workRoot)
    }
}

extension HarnessSkillDirectory {
    init(_ row: FfiHarnessSkillDir) {
        self.init(
            path: row.path,
            exists: row.exists,
            skillCount: row.skillCount,
            uniqueSkillCount: row.uniqueSkillCount,
            sourceSkillCount: row.sourceSkillCount,
            linkedSkillCount: row.linkedSkillCount,
            brokenLinkCount: row.brokenLinkCount
        )
    }
}

extension AgentHarness {
    init(_ row: FfiAgentHarness) {
        self.init(
            agent: row.agent,
            detected: row.detected,
            skillDirectories: row.skillDirs.map(HarnessSkillDirectory.init),
            uniqueSkillCount: row.uniqueSkillCount,
            sourceSkillCount: row.sourceSkillCount,
            linkedSkillCount: row.linkedSkillCount,
            placementCount: row.placementCount,
            brokenLinkCount: row.brokenLinkCount,
            detectedViaApp: row.detectedViaApp,
            detectedViaConfig: row.detectedViaConfig,
            detectedViaSkillDirectory: row.detectedViaSkillDirectory
        )
    }
}

extension HarnessDetectionSummary {
    init(_ row: FfiHarnessDetectionSummary) {
        self.init(
            harnesses: row.harnesses.map(AgentHarness.init),
            uniqueSkillCount: row.uniqueSkillCount,
            placementCount: row.placementCount,
            linkedPlacementCount: row.linkedPlacementCount,
            brokenLinkCount: row.brokenLinkCount
        )
    }
}

extension ConfigViewModel {
    init(_ cfg: FfiConfig) {
        self.init(
            onboardingVersion: cfg.onboardingVersion,
            configError: cfg.configError,
            projectRoots: cfg.projectRoots,
            customRoots: cfg.customRoots,
            appearance: cfg.appearance,
            gitPath: cfg.gitPath,
            npxPath: cfg.npxPath,
            globalDirs: cfg.globalDirs.map(GlobalDir.init)
        )
    }
}

extension RuntimeTool {
    init(_ tool: FfiRuntimeTool) {
        switch tool {
        case .git: self = .git
        case .npx: self = .npx
        }
    }

    var ffi: FfiRuntimeTool {
        switch self {
        case .git: .git
        case .npx: .npx
        }
    }
}

extension RuntimeToolState {
    init(_ state: FfiRuntimeToolState) {
        switch state {
        case .available: self = .available
        case .missing: self = .missing
        case .invalid: self = .invalid
        }
    }
}

extension RuntimeToolStatus {
    init(_ status: FfiRuntimeToolStatus) {
        self.init(
            tool: RuntimeTool(status.tool),
            state: RuntimeToolState(status.state),
            path: status.path,
            version: status.version,
            issue: status.issue
        )
    }
}

extension RuntimeStatus {
    init(_ status: FfiRuntimeStatus) {
        self.init(git: RuntimeToolStatus(status.git), npx: RuntimeToolStatus(status.npx))
    }
}

extension McpClient {
    init(_ client: FfiMcpClient) {
        switch client {
        case .codex: self = .codex
        case .claudeCode: self = .claudeCode
        case .cursor: self = .cursor
        }
    }

    var ffi: FfiMcpClient {
        switch self {
        case .codex: .codex
        case .claudeCode: .claudeCode
        case .cursor: .cursor
        }
    }
}

extension McpClientStatus {
    init(_ status: FfiMcpClientStatus) {
        self.init(
            client: McpClient(status.client),
            detected: status.detected,
            configured: status.configured,
            needsRepair: status.needsRepair,
            conflict: status.conflict,
            configPath: status.configPath,
            issue: status.issue
        )
    }
}

extension McpIntegrationStatus {
    init(_ status: FfiMcpIntegrationStatus) {
        self.init(
            bundledAvailable: status.bundledAvailable,
            installed: status.installed,
            updateAvailable: status.updateAvailable,
            installedPath: status.installedPath,
            clients: status.clients.map(McpClientStatus.init)
        )
    }
}

extension UpdateResult {
    init(_ row: FfiUpdateOutcome) {
        self.init(skillId: row.skillId, name: row.name, ok: row.ok, message: row.message)
    }
}

extension JobProgress {
    init(_ row: FfiProgress) {
        self.init(done: row.done, total: row.total, name: row.name, phase: row.phase)
    }
}

/// Blocking UniFFI calls never exceed Default QoS because Rust worker threads run there.
@MainActor
final class RustBackend: SkillbookBackend {
    private let session = Session()

    private var bundledMcpPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/skillkit-mcp", isDirectory: false)
            .path
    }

    func scan(silent: Bool) async throws -> Snapshot {
        let session = session
        return Snapshot(await run(priority: silent ? .utility : .medium) {
            session.scan(silent: silent)
        })
    }

    func checkUpdates() async throws -> Snapshot {
        let session = session
        return Snapshot(await run { session.checkUpdates() })
    }

    func previewUpdateFile(skillId: String, path: String) async throws -> UpdateFileDiff {
        let session = session
        return try UpdateFileDiff(await run {
            try session.previewUpdateFile(id: skillId, path: path)
        })
    }

    func readSkill(id: String) async throws -> ParsedSkillFile {
        let session = session
        return try ParsedSkillFile(await run { try session.readSkill(id: id) })
    }

    func saveSkill(id: String, yaml: String?, body: String) async throws {
        let session = session
        try await run { try session.saveSkill(id: id, yaml: yaml, body: body) }
    }

    func updateSkill(id: String) async throws -> UpdateResult {
        let session = session
        return try UpdateResult(await run { try session.updateSkill(id: id) })
    }

    func applyUpdates(ids: [String]) async throws -> [UpdateResult] {
        let session = session
        return await run { session.applyUpdates(ids: ids).map(UpdateResult.init) }
    }

    func installSkill(spec: String, skill: String?, global: Bool) async -> UpdateResult {
        let session = session
        return await run { UpdateResult(session.installSkill(spec: spec, skill: skill, global: global)) }
    }

    func installSkillInProject(
        spec: String,
        skill: String?,
        projectRoot: String
    ) async -> UpdateResult {
        let session = session
        return await run {
            UpdateResult(session.installSkillInProject(
                spec: spec,
                skill: skill,
                projectRoot: projectRoot
            ))
        }
    }

    func linkSkill(id: String, projectRoot: String, agents: [String]) async throws -> UpdateResult {
        let session = session
        return try UpdateResult(await run {
            try session.linkSkill(id: id, projectRoot: projectRoot, agents: agents)
        })
    }

    func createSkill(folder: String, name: String, description: String) async throws -> Snapshot {
        let session = session
        return try Snapshot(await run { try session.createSkill(folder: folder, name: name, description: description) })
    }

    func createSkillInFolders(
        folders: [String],
        name: String,
        description: String
    ) async throws -> Snapshot {
        let session = session
        return try Snapshot(await run {
            try session.createSkillInFolders(
                folders: folders,
                name: name,
                description: description
            )
        })
    }

    func createSkillInProject(
        projectRoot: String,
        name: String,
        description: String
    ) async throws -> Snapshot {
        let session = session
        return try Snapshot(await run {
            try session.createSkillInProject(
                projectRoot: projectRoot,
                name: name,
                description: description
            )
        })
    }

    func progress() -> JobProgress {
        JobProgress(session.progress())
    }

    func cancelJob() {
        session.cancelJob()
    }

    func waitForWatchChange() async -> Bool {
        let session = session
        let wait = Task.detached(priority: .utility) { session.waitForWatchChange() }
        return await withTaskCancellationHandler {
            await wait.value
        } onCancel: {
            session.interruptWatchWait()
        }
    }

    func ignoreWatch(ms: UInt32) {
        session.ignoreWatch(ms: ms)
    }

    func config() -> ConfigViewModel {
        ConfigViewModel(session.config())
    }

    func projects() async -> [ProjectCandidate] {
        let session = session
        return await run(priority: .utility) { session.projects().map(ProjectCandidate.init) }
    }

    func detectHarnesses() async -> HarnessDetectionSummary {
        let session = session
        return await run(priority: .utility) {
            HarnessDetectionSummary(session.detectHarnesses())
        }
    }

    func completeOnboarding(projectRoots: [String], customRoots: [String]) async throws -> Snapshot {
        let session = session
        return try Snapshot(await run {
            try session.completeOnboarding(projectRoots: projectRoots, customRoots: customRoots)
        })
    }

    func runtimeStatus() -> RuntimeStatus {
        RuntimeStatus(session.runtimeStatus())
    }

    func refreshRuntime() async -> RuntimeStatus {
        let session = session
        return await run(priority: .utility) { RuntimeStatus(session.refreshRuntime()) }
    }

    func setRuntimeTool(_ tool: RuntimeTool, path: String?) async throws -> RuntimeStatus {
        let session = session
        return try await run {
            RuntimeStatus(try session.setRuntimeTool(tool: tool.ffi, path: path))
        }
    }

    func mcpIntegrationStatus() -> McpIntegrationStatus {
        McpIntegrationStatus(session.mcpIntegrationStatus(bundledPath: bundledMcpPath))
    }

    func installMcpServer() async throws -> McpIntegrationStatus {
        let session = session
        let bundledMcpPath = bundledMcpPath
        return try McpIntegrationStatus(await run {
            try session.installMcpServer(bundledPath: bundledMcpPath)
        })
    }

    func configureMcpClient(_ client: McpClient) async throws -> McpIntegrationStatus {
        let session = session
        let bundledMcpPath = bundledMcpPath
        return try McpIntegrationStatus(await run {
            try session.configureMcpClient(client: client.ffi, bundledPath: bundledMcpPath)
        })
    }

    func disconnectMcpClient(_ client: McpClient) async throws -> McpIntegrationStatus {
        let session = session
        let bundledMcpPath = bundledMcpPath
        return try McpIntegrationStatus(await run {
            try session.disconnectMcpClient(client: client.ffi, bundledPath: bundledMcpPath)
        })
    }

    func addProjectRoot(_ path: String) async throws -> Snapshot {
        let session = session
        return try Snapshot(await run { try session.addProjectRoot(path: path) })
    }

    func removeProjectRoot(_ path: String) async throws -> Snapshot {
        let session = session
        return try Snapshot(await run { try session.removeProjectRoot(path: path) })
    }

    func addCustomRoot(_ path: String) async throws -> Snapshot {
        let session = session
        return try Snapshot(await run { try session.addCustomRoot(path: path) })
    }

    func removeCustomRoot(_ path: String) async throws -> Snapshot {
        let session = session
        return try Snapshot(await run { try session.removeCustomRoot(path: path) })
    }

    func setAppearance(_ mode: String) async throws -> ConfigViewModel {
        let session = session
        return try ConfigViewModel(await run { try session.setAppearance(mode: mode) })
    }

    private func run<T: Sendable>(
        priority: TaskPriority = .medium,
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        do {
            return try await Task.detached(priority: priority, operation: body).value
        } catch let error as SkillbookError {
            throw DisplayedError(errorDescription: error.message)
        }
    }

    private func run<T: Sendable>(
        priority: TaskPriority = .medium,
        _ body: @escaping @Sendable () -> T
    ) async -> T {
        await Task.detached(priority: priority, operation: body).value
    }
}

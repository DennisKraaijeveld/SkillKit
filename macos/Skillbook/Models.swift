import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case read = "Read"
    case source = "Raw"

    var id: String { rawValue }
}

enum SkillScope: String, Comparable, CaseIterable {
    case global = "Global"
    case project = "Project"
    case custom = "Custom"

    static func < (lhs: SkillScope, rhs: SkillScope) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ scope: SkillScope) -> Int {
        switch scope {
        case .global: 0
        case .project: 1
        case .custom: 2
        }
    }
}

enum SkillVersion: String {
    case unknown, checking, upToDate, updateAvailable, untracked, error
}

enum RuntimeTool: String, CaseIterable, Identifiable {
    case git = "Git"
    case npx = "npx"

    var id: String { rawValue }
}

enum RuntimeToolState: Equatable {
    case available, missing, invalid
}

struct RuntimeToolStatus: Equatable {
    var tool: RuntimeTool
    var state: RuntimeToolState
    var path: String?
    var version: String?
    var issue: String?

    var isAvailable: Bool { state == .available }
}

struct RuntimeStatus: Equatable {
    var git: RuntimeToolStatus
    var npx: RuntimeToolStatus

    subscript(tool: RuntimeTool) -> RuntimeToolStatus {
        tool == .git ? git : npx
    }
}

enum McpClient: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode
    case cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        }
    }

    var systemImage: String {
        switch self {
        case .codex: "terminal"
        case .claudeCode: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow"
        }
    }
}

struct McpClientStatus: Equatable, Sendable {
    var client: McpClient
    var detected: Bool
    var configured: Bool
    var needsRepair: Bool
    var conflict: Bool
    var configPath: String
    var issue: String?
}

struct McpIntegrationStatus: Equatable, Sendable {
    var bundledAvailable: Bool
    var installed: Bool
    var updateAvailable: Bool
    var installedPath: String
    var clients: [McpClientStatus]

    subscript(client: McpClient) -> McpClientStatus? {
        clients.first { $0.client == client }
    }
}

struct SkillPlacement: Hashable {
    var agent: String
    var path: String
    var scope: SkillScope
    var root: String?
    var isSymlink: Bool
}

struct DuplicateGroup: Identifiable, Hashable {
    var id: String
    var reason: String
    var skills: [SkillRow]

    var name: String { skills.first?.name ?? "Skill" }
}

enum ProjectSkillDestination: String, CaseIterable, Identifiable {
    case agents, claude, cursor, codex, opencode, gemini, windsurf, github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents: "Shared"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .gemini: "Gemini"
        case .windsurf: "Windsurf"
        case .github: "GitHub Copilot"
        }
    }

    var relativePath: String {
        switch self {
        case .agents: ".agents/skills"
        case .claude: ".claude/skills"
        case .cursor: ".cursor/skills"
        case .codex: ".codex/skills"
        case .opencode: ".opencode/skills"
        case .gemini: ".gemini/skills"
        case .windsurf: ".windsurf/skills"
        case .github: ".github/skills"
        }
    }
}

struct SkillRow: Identifiable, Hashable {
    var id: String
    var name: String
    var description: String
    var scope: SkillScope
    var agents: [String]
    var path: String
    var npx: Bool
    var sourceLabel: String
    var sourceKind: String
    var collectionId: String
    var collectionLabel: String
    var sourceCategory: String?
    var placements: [SkillPlacement]
    var duplicateKey: String
    var exactDuplicateKey: String
    var duplicateReason: String
    var version: SkillVersion
    var bumpFrom: String?
    var bumpTo: String?
    var folder: String
    var skillMd: String
    var githubUrl: String?
    var npxInstall: String?
    var versionError: String?
    var modifiedAt: Date? = nil

    var bumpSummary: String? {
        guard let bumpFrom, let bumpTo else { return nil }
        return "\(bumpFrom) → \(bumpTo)"
    }

    var canUpdate: Bool { version == .updateAvailable }

    var displayTitle: String {
        let acronyms = [
            "aeo": "AEO",
            "ai": "AI",
            "api": "API",
            "chatgpt": "ChatGPT",
            "cli": "CLI",
            "css": "CSS",
            "html": "HTML",
            "mcp": "MCP",
            "openai": "OpenAI",
            "sdk": "SDK",
            "seo": "SEO",
            "sql": "SQL",
            "tdd": "TDD",
            "ui": "UI",
            "ux": "UX",
        ]
        let words = name
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return name }

        return words.enumerated().map { index, word in
            let value = String(word)
            if let acronym = acronyms[value.lowercased()] {
                return acronym
            }
            guard index == 0, let first = value.first else { return value }
            return first.uppercased() + value.dropFirst()
        }
        .joined(separator: " ")
    }
}

struct VersionChange: Identifiable, Hashable {
    var id: String { skillId }
    var skillId: String
    var name: String
    var from: String?
    var to: String?
    var source: String
    var requiresNpx: Bool
    var localModified: Bool
    var files: [UpdateFileChange]
    var summary: String {
        guard let from, let to else { return "Unversioned" }
        return "\(from) → \(to)"
    }
}

struct UpdateFileChange: Identifiable, Hashable {
    var path: String
    var kind: String
    var id: String { "\(kind):\(path)" }
}

struct UpdateFileDiff: Hashable {
    var path: String
    var lines: [UpdateDiffLine]
}

struct UpdateDiffLine: Identifiable, Hashable {
    var kind: String
    var oldLine: UInt32?
    var newLine: UInt32?
    var text: String
    var id: String { "\(kind):\(oldLine ?? 0):\(newLine ?? 0):\(text)" }
}

struct ParsedSkillFile {
    var yaml: String
    var body: String
    var name: String?
    var description: String?
}

struct GlobalDir: Identifiable, Hashable {
    var agent: String
    var path: String
    var exists: Bool
    var id: String { path }
}

struct ProjectCandidate: Identifiable, Hashable {
    var name: String
    var path: String
    var workRoot: String
    var id: String { path }

    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

enum ProjectSearch {
    static func results(
        _ projects: [ProjectCandidate],
        query: String,
        recentPaths: [String]
    ) -> [ProjectCandidate] {
        let query = normalized(query)
        let recency = Dictionary(uniqueKeysWithValues: recentPaths.enumerated().map { ($0.element, $0.offset) })
        guard !query.isEmpty else {
            return projects.sorted { left, right in
                let leftRecent = recency[left.path] ?? Int.max
                let rightRecent = recency[right.path] ?? Int.max
                return leftRecent != rightRecent
                    ? leftRecent < rightRecent
                    : stableOrder(left, right)
            }
        }

        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return projects
            .compactMap { project -> (ProjectCandidate, Int)? in
                guard let score = score(project, query: query, terms: terms) else { return nil }
                return (project, score)
            }
            .sorted { left, right in
                if left.1 != right.1 { return left.1 < right.1 }
                let leftRecent = recency[left.0.path] ?? Int.max
                let rightRecent = recency[right.0.path] ?? Int.max
                return leftRecent != rightRecent
                    ? leftRecent < rightRecent
                    : stableOrder(left.0, right.0)
            }
            .map(\.0)
    }

    private static func score(
        _ project: ProjectCandidate,
        query: String,
        terms: [String]
    ) -> Int? {
        let name = normalized(project.name)
        let path = normalized(project.path)
        let phraseScore = score(query, name: name, path: path)
        guard terms.count > 1 else { return phraseScore }

        var termScore = 0
        for term in terms {
            guard let score = score(term, name: name, path: path) else { return nil }
            termScore += score
        }
        return min(phraseScore ?? Int.max, termScore)
    }

    private static func score(_ term: String, name: String, path: String) -> Int? {
        if name == term { return 0 }
        if name.hasPrefix(term) { return 100 + name.count - term.count }
        if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(term) }) {
            return 200 + name.count - term.count
        }
        if let range = name.range(of: term) {
            return 300 + name.distance(from: name.startIndex, to: range.lowerBound)
        }
        if let gap = subsequenceGap(term, in: name) { return 400 + gap }
        if let range = path.range(of: term) {
            return 600 + path.distance(from: path.startIndex, to: range.lowerBound)
        }
        return nil
    }

    private static func subsequenceGap(_ needle: String, in haystack: String) -> Int? {
        var searchStart = haystack.startIndex
        var firstMatch: String.Index?
        var lastMatch: String.Index?
        for character in needle {
            guard let match = haystack[searchStart...].firstIndex(of: character) else { return nil }
            firstMatch = firstMatch ?? match
            lastMatch = match
            searchStart = haystack.index(after: match)
        }
        guard let firstMatch, let lastMatch else { return nil }
        return haystack.distance(from: firstMatch, to: lastMatch) - needle.count + 1
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableOrder(_ left: ProjectCandidate, _ right: ProjectCandidate) -> Bool {
        let names = left.name.localizedCaseInsensitiveCompare(right.name)
        return names == .orderedSame ? left.path < right.path : names == .orderedAscending
    }
}

struct HarnessSkillDirectory: Identifiable, Hashable {
    var path: String
    var exists: Bool
    var skillCount: UInt32
    var uniqueSkillCount: UInt32
    var sourceSkillCount: UInt32
    var linkedSkillCount: UInt32
    var brokenLinkCount: UInt32
    var id: String { path }
}

struct AgentHarness: Identifiable, Hashable {
    var agent: String
    var detected: Bool
    var skillDirectories: [HarnessSkillDirectory]
    var uniqueSkillCount: UInt32
    var sourceSkillCount: UInt32
    var linkedSkillCount: UInt32
    var placementCount: UInt32
    var brokenLinkCount: UInt32
    var detectedViaApp: Bool
    var detectedViaConfig: Bool
    var detectedViaSkillDirectory: Bool
    var id: String { agent }

    var hasSkillDirectory: Bool {
        skillDirectories.contains(where: \.exists)
    }
}

struct HarnessDetectionSummary: Equatable {
    var harnesses: [AgentHarness]
    var uniqueSkillCount: UInt32
    var placementCount: UInt32
    var linkedPlacementCount: UInt32
    var brokenLinkCount: UInt32

    static let empty = HarnessDetectionSummary(
        harnesses: [],
        uniqueSkillCount: 0,
        placementCount: 0,
        linkedPlacementCount: 0,
        brokenLinkCount: 0
    )
}

struct ConfigViewModel {
    var onboardingVersion: UInt32
    var configError: String?
    var projectRoots: [String]
    var customRoots: [String]
    var appearance: String
    var gitPath: String?
    var npxPath: String?
    var globalDirs: [GlobalDir]

    var onboardingComplete: Bool { onboardingVersion >= 1 }
}

struct Snapshot {
    var skills: [SkillRow]
    var errors: [String]
    var statusHint: String
    var npxBanner: String?
    var versionChanges: [VersionChange]
    var scanning: Bool
}

struct UpdateResult: Equatable, Identifiable {
    var skillId: String
    var name: String
    var ok: Bool
    var message: String
    var id: String { skillId }
}

struct JobProgress: Equatable {
    var done: UInt32
    var total: UInt32
    var name: String
    var phase: String

    static let idle = JobProgress(done: 0, total: 0, name: "", phase: "idle")

    var isIdle: Bool { phase == "idle" || phase.isEmpty }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    var label: String {
        let suffix = name.isEmpty ? "" : " · \(name)"
        switch phase {
        case "check":
            return total > 0 ? "Checking \(done)/\(total)\(suffix)" : "Checking…"
        case "update":
            return total > 0 ? "Updating \(done)/\(total)\(suffix)" : "Updating…"
        case "install":
            return name.isEmpty ? "Installing…" : "Installing \(name)"
        default:
            return ""
        }
    }
}

@MainActor
protocol SkillbookBackend: AnyObject {
    func scan(silent: Bool) async throws -> Snapshot
    func checkUpdates() async throws -> Snapshot
    func previewUpdateFile(skillId: String, path: String) async throws -> UpdateFileDiff
    func readSkill(id: String) async throws -> ParsedSkillFile
    func saveSkill(id: String, yaml: String?, body: String) async throws
    func updateSkill(id: String) async throws -> UpdateResult
    func applyUpdates(ids: [String]) async throws -> [UpdateResult]
    func installSkill(spec: String, skill: String?, global: Bool) async -> UpdateResult
    func installSkillInProject(spec: String, skill: String?, projectRoot: String) async -> UpdateResult
    func linkSkill(id: String, projectRoot: String, agents: [String]) async throws -> UpdateResult
    func createSkill(folder: String, name: String, description: String) async throws -> Snapshot
    func createSkillInFolders(folders: [String], name: String, description: String) async throws -> Snapshot
    func createSkillInProject(projectRoot: String, name: String, description: String) async throws -> Snapshot
    func progress() -> JobProgress
    func cancelJob()
    func waitForWatchChange() async -> Bool
    func ignoreWatch(ms: UInt32)
    func config() -> ConfigViewModel
    func projects() async -> [ProjectCandidate]
    func detectHarnesses() async -> HarnessDetectionSummary
    func completeOnboarding(projectRoots: [String], customRoots: [String]) async throws -> Snapshot
    func runtimeStatus() -> RuntimeStatus
    func refreshRuntime() async -> RuntimeStatus
    func setRuntimeTool(_ tool: RuntimeTool, path: String?) async throws -> RuntimeStatus
    func mcpIntegrationStatus() -> McpIntegrationStatus
    func installMcpServer() async throws -> McpIntegrationStatus
    func configureMcpClient(_ client: McpClient) async throws -> McpIntegrationStatus
    func disconnectMcpClient(_ client: McpClient) async throws -> McpIntegrationStatus
    func addProjectRoot(_ path: String) async throws -> Snapshot
    func removeProjectRoot(_ path: String) async throws -> Snapshot
    func addCustomRoot(_ path: String) async throws -> Snapshot
    func removeCustomRoot(_ path: String) async throws -> Snapshot
    func setAppearance(_ mode: String) async throws -> ConfigViewModel
}

/// In-memory backend for SwiftUI previews and tests.
@MainActor
final class PreviewBackend: SkillbookBackend {
    private var skills: [SkillRow]
    private var files: [String: ParsedSkillFile]
    private var cfg: ConfigViewModel
    private var cancelled = false
    private var mcp = McpIntegrationStatus(
        bundledAvailable: true,
        installed: false,
        updateAvailable: false,
        installedPath: "/Users/demo/Library/Application Support/SkillKit/bin/skillkit-mcp",
        clients: McpClient.allCases.map {
            McpClientStatus(
                client: $0,
                detected: true,
                configured: false,
                needsRepair: false,
                conflict: false,
                configPath: "/Users/demo/.\($0.rawValue)/mcp-config",
                issue: nil
            )
        }
    )

    private(set) var scanCount = 0

    init(onboardingComplete: Bool = true) {
        let demo = SkillRow(
            id: "demo",
            name: "frontend-design",
            description: "Make interfaces shine.",
            scope: .global,
            agents: ["cursor", "claude", "codex"],
            path: "~/.cursor/skills/frontend-design",
            npx: true,
            sourceLabel: "vercel-labs/agent-skills",
            sourceKind: "npx skills",
            collectionId: "skills-cli:vercel-labs/agent-skills",
            collectionLabel: "vercel-labs/agent-skills",
            sourceCategory: "design",
            placements: [
                SkillPlacement(
                    agent: "agents",
                    path: "/Users/demo/.agents/skills/frontend-design",
                    scope: .global,
                    root: nil,
                    isSymlink: false
                ),
                SkillPlacement(
                    agent: "claude",
                    path: "/Users/demo/.claude/skills/frontend-design",
                    scope: .global,
                    root: nil,
                    isSymlink: true
                ),
            ],
            duplicateKey: "skills-cli:vercel-labs/agent-skills:frontend-design",
            exactDuplicateKey: "skills-cli:vercel-labs/agent-skills:frontend-design:preview-demo",
            duplicateReason: "Same skills.sh source",
            version: .updateAvailable,
            bumpFrom: "1.2.3",
            bumpTo: "1.2.5",
            folder: "/Users/demo/.cursor/skills/frontend-design",
            skillMd: "/Users/demo/.cursor/skills/frontend-design/SKILL.md",
            githubUrl: "https://github.com/vercel-labs/agent-skills",
            npxInstall: "npx skills add vercel-labs/agent-skills --skill frontend-design -g",
            versionError: nil,
            modifiedAt: Date().addingTimeInterval(-10_800)
        )
        skills = [demo]
        files = [
            "demo": ParsedSkillFile(
                yaml: "name: frontend-design\ndescription: Make interfaces shine.",
                body: "# Frontend Design\n\n## Usage\n\nUse when building UI.\n\n## Usage\n\nDuplicate heading for outline ids.\n",
                name: "frontend-design",
                description: "Make interfaces shine."
            )
        ]
        cfg = ConfigViewModel(
            onboardingVersion: onboardingComplete ? 1 : 0,
            configError: nil,
            projectRoots: [],
            customRoots: [],
            appearance: "system",
            gitPath: nil,
            npxPath: nil,
            globalDirs: [
                GlobalDir(agent: "cursor", path: "/Users/demo/.cursor/skills", exists: true),
                GlobalDir(agent: "claude", path: "/Users/demo/.claude/skills", exists: false),
            ]
        )
    }

    func scan(silent _: Bool) async throws -> Snapshot {
        scanCount += 1
        return currentSnapshot()
    }
    func checkUpdates() async throws -> Snapshot { currentSnapshot() }

    func previewUpdateFile(skillId _: String, path: String) async throws -> UpdateFileDiff {
        UpdateFileDiff(
            path: path,
            lines: [
                UpdateDiffLine(kind: "context", oldLine: 1, newLine: 1, text: "---"),
                UpdateDiffLine(kind: "context", oldLine: 2, newLine: 2, text: "name: frontend-design"),
                UpdateDiffLine(kind: "removed", oldLine: 3, newLine: nil, text: "description: Make interfaces shine."),
                UpdateDiffLine(kind: "added", oldLine: nil, newLine: 3, text: "description: Design and review polished interfaces."),
                UpdateDiffLine(kind: "context", oldLine: 4, newLine: 4, text: "---"),
            ]
        )
    }

    func readSkill(id: String) async throws -> ParsedSkillFile {
        guard let file = files[id] else { throw PreviewError.missing }
        return file
    }

    func saveSkill(id: String, yaml: String?, body: String) async throws {
        files[id] = ParsedSkillFile(yaml: yaml ?? "", body: body, name: nil, description: nil)
    }

    func updateSkill(id: String) async throws -> UpdateResult {
        if let idx = skills.firstIndex(where: { $0.id == id }) {
            skills[idx].version = .upToDate
            skills[idx].bumpFrom = nil
            skills[idx].bumpTo = nil
            return UpdateResult(skillId: id, name: skills[idx].name, ok: true, message: "updated \(skills[idx].name)")
        }
        return UpdateResult(skillId: id, name: id, ok: false, message: "skill not found")
    }

    func applyUpdates(ids: [String]) async throws -> [UpdateResult] {
        var messages: [UpdateResult] = []
        for id in ids {
            messages.append(try await updateSkill(id: id))
        }
        return messages
    }

    func installSkill(spec: String, skill: String?, global _: Bool) async -> UpdateResult {
        if spec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return UpdateResult(skillId: "install", name: "install", ok: false, message: "paste an npx skills source such as owner/repo")
        }
        let id = skill ?? spec
        return UpdateResult(skillId: id, name: id, ok: true, message: "installed \(spec)")
    }

    func installSkillInProject(
        spec: String,
        skill: String?,
        projectRoot: String
    ) async -> UpdateResult {
        if !cfg.projectRoots.contains(projectRoot) {
            cfg.projectRoots.append(projectRoot)
        }
        return await installSkill(spec: spec, skill: skill, global: false)
    }

    func linkSkill(id: String, projectRoot: String, agents: [String]) async throws -> UpdateResult {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { throw PreviewError.missing }
        if !cfg.projectRoots.contains(projectRoot) {
            cfg.projectRoots.append(projectRoot)
        }
        for agent in agents where !skills[index].placements.contains(where: {
            $0.agent == agent && $0.root == projectRoot
        }) {
            skills[index].placements.append(SkillPlacement(
                agent: agent,
                path: "\(projectRoot)/\(ProjectSkillDestination(rawValue: agent)?.relativePath ?? ".agents/skills")/\(skills[index].name)",
                scope: .project,
                root: projectRoot,
                isSymlink: true
            ))
        }
        return UpdateResult(
            skillId: id,
            name: skills[index].name,
            ok: true,
            message: "Linked \(skills[index].name) to this project"
        )
    }

    func createSkill(folder: String, name: String, description: String) async throws -> Snapshot {
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let id = "\(folder)/\(slug)"
        let row = SkillRow(
            id: id,
            name: slug,
            description: description,
            scope: .global,
            agents: ["cursor"],
            path: "\(folder)/\(slug)",
            npx: false,
            sourceLabel: "local",
            sourceKind: "local",
            collectionId: "local",
            collectionLabel: "Local skills",
            sourceCategory: nil,
            placements: [
                SkillPlacement(
                    agent: "cursor",
                    path: "\(folder)/\(slug)",
                    scope: .global,
                    root: nil,
                    isSymlink: false
                )
            ],
            duplicateKey: "content:\(slug):preview-\(slug)",
            exactDuplicateKey: "content:\(slug):preview-\(slug):preview-\(slug)",
            duplicateReason: "Identical SKILL.md contents",
            version: .untracked,
            bumpFrom: nil,
            bumpTo: nil,
            folder: "\(folder)/\(slug)",
            skillMd: "\(folder)/\(slug)/SKILL.md",
            githubUrl: nil,
            npxInstall: nil,
            versionError: nil
        )
        skills.append(row)
        files[id] = ParsedSkillFile(
            yaml: "name: \(slug)\ndescription: \(description)",
            body: "# \(name)\n\n",
            name: slug,
            description: description
        )
        return currentSnapshot()
    }

    func createSkillInFolders(
        folders: [String],
        name: String,
        description: String
    ) async throws -> Snapshot {
        var seen = Set<String>()
        let folders = folders.filter { seen.insert($0).inserted }
        guard let sourceFolder = folders.first else { throw PreviewError.missing }
        _ = try await createSkill(folder: sourceFolder, name: name, description: description)

        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let id = "\(sourceFolder)/\(slug)"
        guard let index = skills.firstIndex(where: { $0.id == id }) else { throw PreviewError.missing }
        let placements = folders.enumerated().map { offset, folder in
            let agent = cfg.globalDirs.first(where: { $0.path == folder })?.agent
                ?? URL(fileURLWithPath: folder)
                    .deletingLastPathComponent()
                    .lastPathComponent
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return SkillPlacement(
                agent: agent,
                path: "\(folder)/\(slug)",
                scope: .global,
                root: nil,
                isSymlink: offset > 0
            )
        }
        skills[index].agents = placements.map(\.agent)
        skills[index].placements = placements
        return currentSnapshot()
    }

    func createSkillInProject(projectRoot: String, name: String, description: String) async throws -> Snapshot {
        if !cfg.projectRoots.contains(projectRoot) { cfg.projectRoots.append(projectRoot) }
        return try await createSkill(
            folder: "\(projectRoot)/.agents/skills",
            name: name,
            description: description
        )
    }

    func progress() -> JobProgress { cancelled ? .idle : .idle }
    func cancelJob() { cancelled = true }
    func waitForWatchChange() async -> Bool {
        try? await Task.sleep(for: .seconds(60))
        return false
    }
    func ignoreWatch(ms _: UInt32) {}
    func config() -> ConfigViewModel { cfg }
    func projects() async -> [ProjectCandidate] {
        cfg.projectRoots.map {
            ProjectCandidate(
                name: URL(fileURLWithPath: $0).lastPathComponent,
                path: $0,
                workRoot: $0
            )
        }
    }
    func detectHarnesses() async -> HarnessDetectionSummary {
        let harnesses = [
            AgentHarness(
                agent: "agents",
                detected: true,
                skillDirectories: [
                    HarnessSkillDirectory(
                        path: "/Users/demo/.agents/skills",
                        exists: true,
                        skillCount: 1,
                        uniqueSkillCount: 1,
                        sourceSkillCount: 1,
                        linkedSkillCount: 0,
                        brokenLinkCount: 0
                    ),
                ],
                uniqueSkillCount: 1,
                sourceSkillCount: 1,
                linkedSkillCount: 0,
                placementCount: 1,
                brokenLinkCount: 0,
                detectedViaApp: false,
                detectedViaConfig: true,
                detectedViaSkillDirectory: true
            ),
            AgentHarness(
                agent: "cursor",
                detected: true,
                skillDirectories: [
                    HarnessSkillDirectory(
                        path: "/Users/demo/.cursor/skills",
                        exists: true,
                        skillCount: 1,
                        uniqueSkillCount: 1,
                        sourceSkillCount: 1,
                        linkedSkillCount: 0,
                        brokenLinkCount: 0
                    ),
                ],
                uniqueSkillCount: 1,
                sourceSkillCount: 1,
                linkedSkillCount: 0,
                placementCount: 1,
                brokenLinkCount: 0,
                detectedViaApp: true,
                detectedViaConfig: true,
                detectedViaSkillDirectory: true
            ),
            AgentHarness(
                agent: "claude",
                detected: false,
                skillDirectories: [
                    HarnessSkillDirectory(
                        path: "/Users/demo/.claude/skills",
                        exists: false,
                        skillCount: 0,
                        uniqueSkillCount: 0,
                        sourceSkillCount: 0,
                        linkedSkillCount: 0,
                        brokenLinkCount: 0
                    ),
                ],
                uniqueSkillCount: 0,
                sourceSkillCount: 0,
                linkedSkillCount: 0,
                placementCount: 0,
                brokenLinkCount: 0,
                detectedViaApp: false,
                detectedViaConfig: false,
                detectedViaSkillDirectory: false
            ),
        ]
        return HarnessDetectionSummary(
            harnesses: harnesses,
            uniqueSkillCount: 2,
            placementCount: 2,
            linkedPlacementCount: 0,
            brokenLinkCount: 0
        )
    }

    func completeOnboarding(projectRoots: [String], customRoots: [String]) async throws -> Snapshot {
        cfg.projectRoots = Array(Set(projectRoots)).sorted()
        cfg.customRoots = Array(Set(customRoots)).sorted()
        cfg.onboardingVersion = 1
        scanCount += 1
        return currentSnapshot()
    }
    func runtimeStatus() -> RuntimeStatus {
        RuntimeStatus(
            git: RuntimeToolStatus(
                tool: .git,
                state: .available,
                path: "/usr/bin/git",
                version: "2.39.5",
                issue: nil
            ),
            npx: RuntimeToolStatus(
                tool: .npx,
                state: .available,
                path: "/Users/demo/.vite-plus/bin/npx",
                version: "11.19.0",
                issue: nil
            )
        )
    }
    func refreshRuntime() async -> RuntimeStatus { runtimeStatus() }
    func setRuntimeTool(_ tool: RuntimeTool, path: String?) async throws -> RuntimeStatus {
        switch tool {
        case .git: cfg.gitPath = path
        case .npx: cfg.npxPath = path
        }
        return runtimeStatus()
    }

    func mcpIntegrationStatus() -> McpIntegrationStatus { mcp }

    func installMcpServer() async throws -> McpIntegrationStatus {
        mcp.installed = true
        mcp.updateAvailable = false
        return mcp
    }

    func configureMcpClient(_ client: McpClient) async throws -> McpIntegrationStatus {
        mcp.installed = true
        if let index = mcp.clients.firstIndex(where: { $0.client == client }) {
            mcp.clients[index].configured = true
            mcp.clients[index].needsRepair = false
        }
        return mcp
    }

    func disconnectMcpClient(_ client: McpClient) async throws -> McpIntegrationStatus {
        if let index = mcp.clients.firstIndex(where: { $0.client == client }) {
            mcp.clients[index].configured = false
        }
        return mcp
    }

    func addProjectRoot(_ path: String) async throws -> Snapshot {
        if !cfg.projectRoots.contains(path) { cfg.projectRoots.append(path) }
        return currentSnapshot()
    }

    func removeProjectRoot(_ path: String) async throws -> Snapshot {
        cfg.projectRoots.removeAll { $0 == path }
        return currentSnapshot()
    }

    func addCustomRoot(_ path: String) async throws -> Snapshot {
        if !cfg.customRoots.contains(path) { cfg.customRoots.append(path) }
        return currentSnapshot()
    }

    func removeCustomRoot(_ path: String) async throws -> Snapshot {
        cfg.customRoots.removeAll { $0 == path }
        return currentSnapshot()
    }

    func setAppearance(_ mode: String) async throws -> ConfigViewModel {
        cfg.appearance = mode
        return cfg
    }

    private func currentSnapshot() -> Snapshot {
        let changes = skills.compactMap { skill -> VersionChange? in
            guard let from = skill.bumpFrom, let to = skill.bumpTo else { return nil }
            return VersionChange(
                skillId: skill.id,
                name: skill.name,
                from: from,
                to: to,
                source: skill.collectionLabel,
                requiresNpx: skill.npx,
                localModified: false,
                files: [
                    UpdateFileChange(path: "SKILL.md", kind: "modified"),
                    UpdateFileChange(path: "references/design.md", kind: "added"),
                ]
            )
        }
        return Snapshot(
            skills: skills,
            errors: [],
            statusHint: changes.isEmpty ? "\(skills.count) skills" : "\(changes.count) updates",
            npxBanner: changes.isEmpty ? nil : "npx skills · \(changes.count) global update · vercel-labs/agent-skills",
            versionChanges: changes,
            scanning: false
        )
    }
}

enum PreviewError: Error { case missing }

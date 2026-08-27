import AppKit
import Foundation
import MarkdownEngine
import Testing
@testable import Skillbook

@Suite("Swift models")
struct ModelsTests {
    @Test("Skill titles turn slugs into sentence case and preserve common acronyms")
    func skillDisplayTitle() {
        let skill = sidebarSkill(
            name: "seo-aeo-best-practices",
            category: "content",
            placements: [
                SkillPlacement(
                    agent: "codex",
                    path: "/Users/demo/.codex/skills/seo-aeo-best-practices",
                    scope: .global,
                    root: nil,
                    isSymlink: false
                )
            ]
        )

        #expect(skill.displayTitle == "SEO AEO best practices")
    }

    @Test("Project search ranks names, fuzzy matches, paths, and recents")
    func projectSearchRanking() {
        let projects = [
            ProjectCandidate(name: "Skillbook", path: "/Users/demo/Work/skillbook", workRoot: "/Users/demo/Work"),
            ProjectCandidate(name: "Site.nu CRM", path: "/Users/demo/Work/sitenu-crm", workRoot: "/Users/demo/Work"),
            ProjectCandidate(name: "Website", path: "/Users/demo/Clients/acme/website", workRoot: "/Users/demo/Clients"),
        ]

        #expect(ProjectSearch.results(projects, query: "site", recentPaths: []).first?.name == "Site.nu CRM")
        #expect(ProjectSearch.results(projects, query: "skbk", recentPaths: []).first?.name == "Skillbook")
        #expect(ProjectSearch.results(projects, query: "acme", recentPaths: []).first?.name == "Website")
        #expect(
            ProjectSearch.results(
                projects,
                query: "",
                recentPaths: ["/Users/demo/Clients/acme/website"]
            ).first?.name == "Website"
        )

        let worktree = ProjectCandidate(
            name: "route-titles",
            path: "/Users/demo/Work/sitenu-crm/.claude/worktrees/route-titles",
            workRoot: "/Users/demo/Work"
        )
        #expect(ProjectSearch.results([worktree], query: "sitenu route", recentPaths: []) == [worktree])

        let unrelated = ProjectCandidate(
            name: "alpha",
            path: "/Users/demo/Work/alpha",
            workRoot: "/Users/demo/Work"
        )
        #expect(ProjectSearch.results([unrelated], query: "udw", recentPaths: []).isEmpty)
    }

    @Test("Project picker hover does not request scrolling")
    func projectPickerHoverDoesNotRequestScrolling() {
        var navigation = ProjectComboBoxNavigation()
        navigation.reset(to: "/projects/first")
        let scrollPath = navigation.scrollPath

        navigation.hover("/projects/second", isInside: true)

        #expect(navigation.keyboardPath == "/projects/first")
        #expect(navigation.hoveredPath == "/projects/second")
        #expect(navigation.scrollPath == scrollPath)
    }

    @Test("Project picker arrows own highlight and scrolling")
    func projectPickerKeyboardNavigation() {
        let paths = ["/projects/first", "/projects/second", "/projects/third"]
        var navigation = ProjectComboBoxNavigation()
        navigation.reset(to: paths[0])
        navigation.hover(paths[2], isInside: true)

        #expect(navigation.move(.down, through: paths) == paths[1])
        #expect(navigation.keyboardPath == paths[1])
        #expect(navigation.hoveredPath == nil)
        #expect(navigation.scrollPath == paths[1])
    }

    @Test("Scope ordering stays stable")
    func scopeOrdering() {
        #expect(SkillScope.allCases.sorted() == [.global, .project, .custom])
    }

    @Test("Progress labels and fractions describe active jobs")
    func progressPresentation() {
        let progress = JobProgress(done: 2, total: 4, name: "frontend-design", phase: "update")

        #expect(progress.fraction == 0.5)
        #expect(progress.label == "Updating 2/4 · frontend-design")
        #expect(!progress.isIdle)
        #expect(JobProgress.idle.isIdle)
    }

    @Test("App update phases expose toolbar and progress states")
    func appUpdatePresentation() {
        let available = AppUpdatePhase.available(version: "0.2.0")
        let downloading = AppUpdatePhase.downloading(version: "0.2.0")
        let ready = AppUpdatePhase.ready(version: "0.2.0")

        #expect(available.showsToolbarItem)
        #expect(!available.isWorking)
        #expect(downloading.showsToolbarItem)
        #expect(downloading.isWorking)
        #expect(ready.showsToolbarItem)
        #expect(!ready.isWorking)
        #expect(ready.title == "SkillKit 0.2.0 is ready")
    }

    @Test("Last checked status avoids a zero-second timestamp")
    @MainActor
    func lastCheckedStatus() {
        let model = AppModel(backend: PreviewBackend())
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        model.lastCheckedAt = checkedAt

        #expect(model.lastCheckedLabel(relativeTo: checkedAt) == "Checked just now")
        #expect(model.lastCheckedLabel(relativeTo: checkedAt.addingTimeInterval(60)) == "Checked 1 min. ago")
    }

    @Test("Frontmatter requires nonempty name and description")
    @MainActor
    func frontmatterValidation() {
        #expect(AppModel.frontmatterIssue("name: demo\ndescription: Useful skill") == nil)
        #expect(AppModel.frontmatterIssue("name: demo") == "YAML needs a description")
        #expect(AppModel.frontmatterIssue("description: Useful skill") == "YAML needs a name")
        #expect(AppModel.frontmatterIssue("  \n") != nil)
    }

    @Test("Markdown model preserves semantic blocks and stable outline ids")
    func markdownBlocks() throws {
        let source = """
        # Heading

        First paragraph.

        ## Usage

        - [x] Parse the document
        - Render the result

        ```swift
        let value = 1

        print(value)
        ```

        Final paragraph.
        """

        let content = MarkdownContent(source: source)

        #expect(content.outline.map(\.id) == ["heading", "usage"])
        #expect(content.outline.first?.sourceRange.location == 0)
        #expect(content.outline.first?.preview == "First paragraph.")
        #expect(content.outline.last?.preview.contains("Parse the document") == true)
        #expect(content.blocks.count == 6)
        guard case let .code(language, code) = content.blocks[4].kind else {
            Issue.record("Expected a code block")
            return
        }
        #expect(language == "swift")
        #expect(code.contains("print(value)"))
    }

    @Test("Reader hides only a duplicate leading title")
    func duplicateMarkdownTitle() {
        let content = MarkdownContent(source: "# Frontend Design\n\n## Workflow\n\nDo the work.")

        #expect(content.blocks(hidingDuplicateTitle: "frontend-design").count == 2)
        #expect(content.outline(hidingDuplicateTitle: "frontend-design").map(\.title) == ["Workflow"])
        #expect(content.blocks(hidingDuplicateTitle: "Another skill").count == 3)
    }

    @Test("Reader jump and active marker share header-aware coordinates")
    func readerScrollCoordinates() {
        let fragmentMinY: CGFloat = 820
        let textViewMinY: CGFloat = 112
        let textContainerOriginY: CGFloat = 18
        let viewportHeight: CGFloat = 600
        let scrollOriginY = ReaderScrollGeometry.scrollOriginY(
            fragmentMinY: fragmentMinY,
            textViewMinY: textViewMinY,
            textContainerOriginY: textContainerOriginY,
            contentInsetTop: 0,
            viewportHeight: viewportHeight
        )
        let activeReferenceY = ReaderScrollGeometry.textContainerY(
            scrollOriginY: scrollOriginY,
            viewportHeight: viewportHeight,
            textViewMinY: textViewMinY,
            textContainerOriginY: textContainerOriginY
        )

        #expect(activeReferenceY > fragmentMinY)
        #expect(activeReferenceY - fragmentMinY == viewportHeight * 0.02)
    }

    @Test("Reader navigation ignores scroll-derived updates until the latest jump completes")
    func readerNavigationGate() {
        var gate = ReaderNavigationGate()
        let first = gate.begin()
        let second = gate.begin()

        #expect(gate.isActive)
        let finishedFirst = gate.finish(first)
        #expect(!finishedFirst)
        #expect(gate.isActive)
        let finishedSecond = gate.finish(second)
        #expect(finishedSecond)
        #expect(!gate.isActive)
    }

    @Test("Reader resolves relative Markdown links inside the skill folder")
    func relativeMarkdownLinkDestination() throws {
        let skillFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let referencesFolder = skillFolder
            .appendingPathComponent("references", isDirectory: true)
        let workersFolder = referencesFolder
            .appendingPathComponent("workers", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workersFolder,
            withIntermediateDirectories: true
        )
        try "# Workers\n".write(
            to: workersFolder.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: skillFolder) }
        let destination = try #require(URL(string: "references/state-scheduling.md"))

        #expect(
            MarkdownLinkDestination.resolve(destination, relativeTo: skillFolder)
                == .skillDocument(
                    referencesFolder.appendingPathComponent("state-scheduling.md")
                )
        )

        let directoryDestination = try #require(URL(string: "references/workers/"))
        #expect(
            MarkdownLinkDestination.resolve(directoryDestination, relativeTo: skillFolder)
                == .skillDocument(
                    workersFolder.appendingPathComponent("README.md")
                )
        )

        let source = "[State scheduling](references/state-scheduling.md) and [Cloudflare](https://developers.cloudflare.com)"
        let readerSource = MarkdownReaderLinks.source(
            source,
            documentURL: skillFolder.appendingPathComponent("SKILL.md"),
            skillFolder: skillFolder
        )
        let encoded = Data("references/state-scheduling.md".utf8).base64EncodedString()
        #expect(
            readerSource
                == "[[State scheduling|skillbook-internal:\(encoded)]] and [Cloudflare](https://developers.cloudflare.com)"
        )
        #expect(
            MarkdownReaderLinks.destination(from: "skillbook-internal:\(encoded)")
                == "references/state-scheduling.md"
        )
        #expect(MarkdownReaderLinks.storageSource(readerSource) == source)
        #expect(
            SkillbookMarkdownLinkResolver().resolve(
                displayName: "skillbook-internal:\(encoded)",
                range: NSRange(location: 0, length: 1)
            ) == WikiLinkResolution(
                id: "skillbook-internal:\(encoded)",
                exists: true
            )
        )

        let cloudflareSource = "| Workers | `references/workers/` |"
        let cloudflareReaderSource = MarkdownReaderLinks.source(
            cloudflareSource,
            documentURL: skillFolder.appendingPathComponent("SKILL.md"),
            skillFolder: skillFolder
        )
        let directoryEncoded = Data("references/workers/".utf8).base64EncodedString()
        #expect(
            cloudflareReaderSource
                == "| Workers | [[references/workers/|skillbook-path:\(directoryEncoded)]] |"
        )
        #expect(MarkdownReaderLinks.storageSource(cloudflareReaderSource) == cloudflareSource)
        #expect(
            MarkdownReaderLinks.destination(from: "skillbook-path:\(directoryEncoded)")
                == "references/workers/"
        )

        let codeExample = "`[State scheduling](references/state-scheduling.md)`\n\n```md\n[State scheduling](references/state-scheduling.md)\n```"
        #expect(
            MarkdownReaderLinks.source(
                codeExample,
                documentURL: skillFolder.appendingPathComponent("SKILL.md"),
                skillFolder: skillFolder
            ) == codeExample
        )

        let parentDestination = try #require(URL(string: "../../outside.md"))
        #expect(
            MarkdownLinkDestination.resolve(
                parentDestination,
                relativeTo: skillFolder.appendingPathComponent("references", isDirectory: true),
                within: skillFolder
            ) == .external(parentDestination)
        )
    }

    @Test("Editor keeps transformed links in one stable presentation buffer")
    func stableMarkdownEditorPresentation() {
        let storedText = """
        ```swift
        let value = 1
        ```

        [Reference](references/state.md)
        """
        let identifier = Data("references/state.md".utf8).base64EncodedString()
        let presentedText = storedText.replacingOccurrences(
            of: "[Reference](references/state.md)",
            with: "[[Reference|skillbook-internal:\(identifier)]]"
        )
        var transformCount = 0
        var buffer = MarkdownEditorTextBuffer()

        buffer.synchronize(storedText: storedText) { _ in
            transformCount += 1
            return presentedText
        }
        let updatedStoredText = buffer.update(presentedText + "\n")
        buffer.synchronize(storedText: updatedStoredText) { _ in
            transformCount += 1
            return "unexpected retransform"
        }

        #expect(buffer.presentedText == presentedText + "\n")
        #expect(updatedStoredText == storedText + "\n")
        #expect(transformCount == 1)
    }

    @Test("Surface palette preserves the light and dark ramps")
    func surfacePalette() {
        #expect(SkillbookSurfaceLevel.allCases.map(\.lightHex) == [
            0xFAFAFA, 0xFCFCFC, 0xFFFFFF, 0xFFFFFF,
            0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
        ])
        #expect(SkillbookSurfaceLevel.allCases.map(\.darkHex) == [
            0x171717, 0x1E1E1E, 0x252525, 0x2C2C2C,
            0x333333, 0x3A3A3A, 0x414141, 0x484848,
        ])
    }

    @Test("Known agent tools use provider assets")
    func providerAssets() throws {
        let codex = try #require(SkillHost(agent: "openai"))
        let openClaw = try #require(SkillHost(agent: "openclaw"))

        #expect(codex == .codex)
        #expect(codex.assetName == "LogoOpenAI")
        #expect(openClaw.assetName == "LogoOpenClaw")
        #expect(SkillHost(agent: "unknown") == nil)
    }

    @Test("Shortcut defaults stay unique and use a primary modifier")
    func shortcutDefaults() {
        let shortcuts = AppShortcutAction.allCases.map(\.defaultShortcut)
        let allUsePrimaryModifier = shortcuts.allSatisfy { $0.hasPrimaryModifier }

        #expect(Set(shortcuts).count == shortcuts.count)
        #expect(allUsePrimaryModifier)
        #expect(AppShortcutAction.editView.defaultShortcut.displayName == "⌘1")
        #expect(AppShortcutAction.searchSkills.defaultShortcut.displayName == "⌥⌘F")
    }

    @Test("Shortcut overrides persist and reject conflicts")
    @MainActor
    func shortcutOverrides() throws {
        let suiteName = "shortcut-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ShortcutSettings(defaults: defaults)
        let custom = AppShortcut(key: "e", modifiers: [.command, .shift])
        #expect(settings.assign(custom, to: .editView) == nil)
        #expect(settings.shortcut(for: .editView) == custom)

        let reloaded = ShortcutSettings(defaults: defaults)
        #expect(reloaded.shortcut(for: .editView) == custom)
        #expect(reloaded.assign(custom, to: .readView) == .conflict(.editView))
        #expect(reloaded.shortcut(for: .readView) == AppShortcutAction.readView.defaultShortcut)

        #expect(reloaded.restoreDefault(for: .editView) == nil)
        #expect(reloaded.shortcut(for: .editView) == AppShortcutAction.editView.defaultShortcut)

        let commandFour = AppShortcut(key: "4", modifiers: .command)
        #expect(reloaded.assign(commandFour, to: .readView) == nil)
        #expect(reloaded.assign(AppShortcutAction.readView.defaultShortcut, to: .editView) == nil)
        #expect(reloaded.restoreDefault(for: .readView) == .conflict(.editView))
        #expect(reloaded.assign(AppShortcut(key: "x", modifiers: .shift), to: .rawView) == .needsModifier)
    }

    @Test("Markdown code blocks have a surface and syntax colors")
    @MainActor
    func markdownCodeStyle() throws {
        let highlighter = SkillbookMarkdownCodeStyle.highlighter
        #expect(highlighter.backgroundColor().alphaComponent > 0.9)

        let highlighted = try #require(
            highlighter.highlight(
                code: "import Foundation\nlet enabled = true\nprint(enabled)",
                language: "swift"
            )
        )
        var colors = Set<String>()
        highlighted.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: highlighted.length)
        ) { value, _, _ in
            guard let color = value as? NSColor else { return }
            colors.insert(color.description)
        }
        #expect(colors.count > 1)
    }

    @Test("Sidebar shows global skills once and flattens project-specific skills")
    func sidebarLocationsAndCollections() throws {
        let global = SkillPlacement(
            agent: "agents",
            path: "/Users/demo/.agents/skills/shared",
            scope: .global,
            root: nil,
            isSymlink: false
        )
        let project = SkillPlacement(
            agent: "agents",
            path: "/Users/demo/Work/product/.agents/skills/shared",
            scope: .project,
            root: "/Users/demo/Work/product",
            isSymlink: true
        )
        var skills = (0..<6).map { index in
            sidebarSkill(
                name: index == 0 ? "shared" : "skill-\(index)",
                category: index.isMultiple(of: 2) ? "engineering" : "productivity",
                placements: index == 0 ? [global, project] : [global]
            )
        }
        skills.append(sidebarSkill(
            name: "project-only",
            category: "project",
            placements: [SkillPlacement(
                agent: "agents",
                path: "/Users/demo/Work/product/.agents/skills/project-only",
                scope: .project,
                root: "/Users/demo/Work/product",
                isSymlink: false
            )],
            scope: .project
        ))

        let tree = SidebarTree.build(skills: skills)
        let globalSection = try #require(tree.first { $0.scope == .global })
        let projectSection = try #require(tree.first { $0.scope == .project })
        let globalCollection = try #require(globalSection.locations.first?.collections.first)
        let projectLocation = try #require(projectSection.locations.first)

        #expect(globalCollection.title == "acme/skill-pack")
        #expect(globalCollection.skillCount == 6)
        #expect(globalCollection.categories.map(\.title) == ["Engineering", "Productivity"])
        #expect(projectLocation.title == "product")
        #expect(projectLocation.path == "/Users/demo/Work/product")
        #expect(projectLocation.collections.isEmpty)
        #expect(projectLocation.skills.map(\.skill.name) == ["project-only"])
        #expect(projectLocation.allSkills.contains { $0.skill.name == "shared" } == false)
    }

    @Test("Duplicate checker ignores linked placements and finds independent copies")
    @MainActor
    func duplicateGroups() {
        let global = SkillPlacement(
            agent: "agents",
            path: "/Users/demo/.agents/skills/shared",
            scope: .global,
            root: nil,
            isSymlink: false
        )
        let project = SkillPlacement(
            agent: "claude",
            path: "/Users/demo/Work/product/.claude/skills/shared",
            scope: .project,
            root: "/Users/demo/Work/product",
            isSymlink: true
        )
        var independent = sidebarSkill(
            name: "shared",
            category: "engineering",
            placements: [global, project]
        )
        let model = AppModel(backend: PreviewBackend())
        model.skills = [independent]
        #expect(model.duplicateGroups.isEmpty)

        independent.id = "/independent/shared"
        independent.folder = "/independent/shared"
        independent.placements = [SkillPlacement(
            agent: "cursor",
            path: "/independent/shared",
            scope: .project,
            root: "/independent",
            isSymlink: false
        )]
        model.skills.append(independent)

        #expect(model.duplicateGroups.count == 1)
        #expect(model.duplicateCopyCount == 1)
    }

    @Test("Catalog projections update only from catalog and filter inputs")
    @MainActor
    func catalogProjections() {
        let placement = SkillPlacement(
            agent: "agents",
            path: "/Users/demo/.agents/skills/skill-0",
            scope: .global,
            root: nil,
            isSymlink: false
        )
        var current = sidebarSkill(name: "skill-0", category: "engineering", placements: [placement])
        var outdated = sidebarSkill(name: "skill-1", category: "productivity", placements: [placement])
        outdated.version = .updateAvailable
        current.description = "Fast local workflows"
        outdated.description = "Remote release workflows"
        let model = AppModel(backend: PreviewBackend())

        model.skills = [current, outdated]
        #expect(model.filtered.count == 2)
        #expect(model.sidebarSections.first?.skillCount == 2)
        #expect(model.availableUpdateCount == 1)

        model.query = " RELEASE "
        #expect(model.filtered.map(\.id) == [outdated.id])
        #expect(model.sidebarSections.first?.skillCount == 1)

        model.query = ""
        model.outdatedOnly = true
        #expect(model.filtered.map(\.id) == [outdated.id])
    }

    @Test("Dirty state tracks editor changes without composing the document")
    @MainActor
    func dirtyState() {
        let model = AppModel(backend: PreviewBackend())
        model.yaml = "name: demo\ndescription: Demo"
        model.bodyText = "# Demo\n"

        #expect(model.dirty)
        model.confirmPending()
        #expect(!model.dirty)

        model.bodyText += "\nChanged"
        #expect(model.dirty)
    }

}

private func sidebarSkill(
    name: String,
    category: String,
    placements: [SkillPlacement],
    scope: SkillScope = .global
) -> SkillRow {
    SkillRow(
        id: "/canonical/\(name)",
        name: name,
        description: "\(name) description",
        scope: scope,
        agents: ["agents"],
        path: placements[0].path,
        npx: true,
        sourceLabel: "acme/skill-pack",
        sourceKind: "npx skills",
        collectionId: "skills-cli:acme/skill-pack",
        collectionLabel: "acme/skill-pack",
        sourceCategory: category,
        placements: placements,
        duplicateKey: "skills-cli:acme/skill-pack:\(name)",
        duplicateReason: "Same skills.sh source",
        version: .upToDate,
        bumpFrom: nil,
        bumpTo: nil,
        folder: "/canonical/\(name)",
        skillMd: "/canonical/\(name)/SKILL.md",
        githubUrl: "https://github.com/acme/skill-pack",
        npxInstall: nil,
        versionError: nil
    )
}

@Suite("Preview backend")
@MainActor
struct PreviewBackendTests {
    @Test("Mandatory setup avoids the initial scan and completes with one scan")
    func onboardingLifecycle() async throws {
        let backend = PreviewBackend(onboardingComplete: false)
        let model = AppModel(backend: backend)

        #expect(!model.onboardingComplete)
        #expect(model.status == "Setup required")
        #expect(backend.scanCount == 0)

        await model.detectHarnesses()
        #expect(model.harnesses.contains { $0.agent == "cursor" && $0.detected })
        #expect(model.harnessDetection.uniqueSkillCount == 2)
        #expect(model.harnessDetection.placementCount == 2)

        let completed = await model.completeOnboarding(
            projectRoots: ["/Users/demo/Work/product", "/Users/demo/Work/product"],
            customRoots: ["/Users/demo/Skills"]
        )

        #expect(completed)
        #expect(model.onboardingComplete)
        #expect(backend.scanCount == 1)
        #expect(model.config.projectRoots == ["/Users/demo/Work/product"])
        #expect(model.config.customRoots == ["/Users/demo/Skills"])
    }

    @Test("Update preview returns a unified line diff")
    func updatePreview() async throws {
        let backend = PreviewBackend()
        let diff = try await backend.previewUpdateFile(skillId: "demo", path: "SKILL.md")

        #expect(diff.path == "SKILL.md")
        #expect(diff.lines.contains { $0.kind == "removed" && $0.oldLine == 3 })
        #expect(diff.lines.contains { $0.kind == "added" && $0.newLine == 3 })
    }

    @Test("Update transitions the preview skill to current")
    func updateLifecycle() async throws {
        let backend = PreviewBackend()
        let before = try await backend.scan(silent: false)

        #expect(before.versionChanges.count == 1)
        #expect(before.skills.first?.version == .updateAvailable)

        let result = try await backend.updateSkill(id: "demo")
        let after = try await backend.scan(silent: true)

        #expect(result.ok)
        #expect(result.skillId == "demo")
        #expect(after.versionChanges.isEmpty)
        #expect(after.skills.first?.version == .upToDate)
    }

    @Test("Creating a skill returns it in the next snapshot")
    func createSkill() async throws {
        let backend = PreviewBackend()
        let snapshot = try await backend.createSkill(
            folder: "/tmp/skills",
            name: "Release Notes",
            description: "Prepare release notes"
        )

        let created = try #require(snapshot.skills.first { $0.name == "release-notes" })
        #expect(created.skillMd == "/tmp/skills/release-notes/SKILL.md")
        #expect(created.version == .untracked)
    }

    @Test("Creating a skill in several folders keeps one shared model")
    func createSkillInFolders() async throws {
        let backend = PreviewBackend()
        let snapshot = try await backend.createSkillInFolders(
            folders: ["/tmp/.agents/skills", "/tmp/.claude/skills"],
            name: "Release Notes",
            description: "Prepare release notes"
        )

        let created = try #require(snapshot.skills.first { $0.name == "release-notes" })
        #expect(created.placements.count == 2)
        #expect(created.placements.filter(\.isSymlink).count == 1)
        #expect(Set(created.agents) == ["agents", "claude"])
    }

    @Test("Custom roots are deduplicated")
    func customRootDeduplication() async throws {
        let backend = PreviewBackend()

        _ = try await backend.addCustomRoot("/tmp/team-skills")
        _ = try await backend.addCustomRoot("/tmp/team-skills")

        #expect(backend.config().customRoots == ["/tmp/team-skills"])
    }

    @Test("MCP setup installs, connects, and disconnects a client")
    func mcpLifecycle() async throws {
        let model = AppModel(backend: PreviewBackend())

        #expect(!model.mcp.installed)
        #expect(model.mcp[.codex]?.configured == false)

        _ = try await model.installMcpServer()
        _ = try await model.configureMcpClient(.codex)

        #expect(model.mcp.installed)
        #expect(model.mcp[.codex]?.configured == true)

        _ = try await model.disconnectMcpClient(.codex)

        #expect(model.mcp.installed)
        #expect(model.mcp[.codex]?.configured == false)
    }

    @Test("Linking a skill registers the project and adds symlink placements")
    func linkToProject() async throws {
        let backend = PreviewBackend()
        let before = try await backend.scan(silent: false)
        let id = try #require(before.skills.first?.id)

        let result = try await backend.linkSkill(
            id: id,
            projectRoot: "/Users/demo/Work/product",
            agents: ["claude", "codex"]
        )
        let after = try await backend.scan(silent: false)

        #expect(result.ok)
        #expect(backend.config().projectRoots == ["/Users/demo/Work/product"])
        #expect(after.skills[0].placements.count(where: \.isSymlink) == 3)
    }
}

import XCTest

final class PerformanceTests: XCTestCase {
    func testSidebarProjectionPerformance() {
        let skills = (0..<1_000).map(Self.skill)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            _ = SidebarTree.build(skills: skills)
        }
    }

    func testMarkdownParsingPerformance() {
        let source = (0..<500)
            .map { "## Section \($0)\n\nA paragraph with **formatting**, [a link](https://example.com), and `code`." }
            .joined(separator: "\n\n")

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            _ = MarkdownContent(source: source)
        }
    }

    private static func skill(_ index: Int) -> SkillRow {
        let category = index.isMultiple(of: 2) ? "engineering" : "productivity"
        let name = "skill-\(index)"
        return SkillRow(
            id: "/canonical/\(name)",
            name: name,
            description: "Performance fixture \(index)",
            scope: .global,
            agents: ["agents", "cursor"],
            path: "~/.agents/skills/\(name)",
            npx: true,
            sourceLabel: "acme/skill-pack",
            sourceKind: "npx skills",
            collectionId: "skills-cli:acme/skill-pack",
            collectionLabel: "acme/skill-pack",
            sourceCategory: category,
            placements: [
                SkillPlacement(
                    agent: "agents",
                    path: "/Users/demo/.agents/skills/\(name)",
                    scope: .global,
                    root: nil,
                    isSymlink: false
                )
            ],
            duplicateKey: "skills-cli:acme/skill-pack:\(name)",
            exactDuplicateKey: "skills-cli:acme/skill-pack:\(name):fixture-\(index)",
            duplicateReason: "Same skills.sh source",
            version: index.isMultiple(of: 10) ? .updateAvailable : .upToDate,
            bumpFrom: nil,
            bumpTo: nil,
            folder: "/canonical/\(name)",
            skillMd: "/canonical/\(name)/SKILL.md",
            githubUrl: "https://github.com/acme/skill-pack",
            npxInstall: nil,
            versionError: nil
        )
    }
}

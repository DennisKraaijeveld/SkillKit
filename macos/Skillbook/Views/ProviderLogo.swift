import AppKit
import SwiftUI

struct SkillbookLogo: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("SkillKit")
    }
}

/// Tools that actually host a skill. The `.agents` folder is the skills.sh
/// library, not a product, so it is not a host.
enum SkillHost: String, Hashable, Identifiable, CaseIterable {
    case claude, cursor, codex, opencode, gemini, copilot, windsurf, github, openclaw
    case crush, devin, goose, kimchi

    var id: String { rawValue }

    init?(agent: String) {
        switch agent.lowercased() {
        case "claude": self = .claude
        case "cursor": self = .cursor
        case "codex", "openai": self = .codex
        case "opencode": self = .opencode
        case "gemini": self = .gemini
        case "copilot": self = .copilot
        case "windsurf": self = .windsurf
        case "github": self = .github
        case "openclaw": self = .openclaw
        case "crush": self = .crush
        case "devin": self = .devin
        case "goose": self = .goose
        case "kimchi": self = .kimchi
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .gemini: "Gemini"
        case .copilot: "Copilot"
        case .windsurf: "Windsurf"
        case .github: "GitHub"
        case .openclaw: "OpenClaw"
        case .crush: "Crush"
        case .devin: "Devin"
        case .goose: "Goose"
        case .kimchi: "Kimchi"
        }
    }

    var assetName: String {
        switch self {
        case .claude: "LogoClaude"
        case .cursor: "LogoCursor"
        case .codex: "LogoOpenAI"
        case .opencode: "LogoOpenCode"
        case .gemini: "LogoGemini"
        case .copilot: "LogoCopilot"
        case .windsurf: "LogoWindsurf"
        case .github: "LogoGitHub"
        case .openclaw: "LogoOpenClaw"
        case .crush: "LogoCrush"
        case .devin: "LogoDevin"
        case .goose: "LogoGoose"
        case .kimchi: "LogoKimchi"
        }
    }

    var usesTemplateRendering: Bool {
        switch self {
        case .cursor, .codex, .opencode, .copilot, .windsurf, .github, .goose: true
        case .claude, .gemini, .openclaw, .crush, .devin, .kimchi: false
        }
    }
}

enum SkillOrigin: Equatable {
    case skillsSh
    case git
    case local
}

extension SkillRow {
    var hosts: [SkillHost] {
        var seen = Set<SkillHost>()
        var out: [SkillHost] = []
        for name in agents {
            guard let host = SkillHost(agent: name), seen.insert(host).inserted else { continue }
            out.append(host)
        }
        return out
    }

    var origin: SkillOrigin {
        if npx { return .skillsSh }
        if sourceKind == "git" { return .git }
        return .local
    }

    var toolNames: [String] {
        var seen = Set<String>()
        return agents.compactMap { name in
            let normalized = name.lowercased()
            guard normalized != "agents", normalized != "local", seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }
}

struct ProviderLogo: View {
    let host: SkillHost

    @ViewBuilder
    var body: some View {
        if host.usesTemplateRendering {
            Image(host.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(nsColor: .labelColor))
                .accessibilityLabel(host.title)
        } else {
            Image(host.assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(host.title)
        }
    }
}

struct ToolMark: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if name == "agents" {
                Image("LogoSkillsSh")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(width: opticalSize, height: opticalSize)
                    .accessibilityLabel("Shared Agent Skills")
            } else if let host = SkillHost(agent: name) {
                ProviderLogo(host: host)
                    .frame(width: opticalSize, height: opticalSize)
            } else {
                Image(systemName: fallbackSymbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: size * 0.64, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .accessibilityLabel(displayName)
            }
        }
        .frame(width: size, height: size)
    }

    private var opticalSize: CGFloat {
        let scale: CGFloat = switch name.lowercased() {
        case "agents": 1
        case "codex", "openai": 0.8
        case "opencode": 0.78
        case "cursor", "windsurf": 0.84
        case "copilot": 0.86
        case "gemini", "openclaw", "devin": 0.82
        case "crush", "goose", "kimchi": 0.88
        case "claude": 0.8
        default: 0.82
        }
        return size * scale
    }

    private var displayName: String {
        name.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private var fallbackSymbol: String {
        toolFallbackSymbol(name)
    }
}

struct ToolMenuIcon: View {
    let name: String

    var body: some View {
        Image(nsImage: menuImage)
            .accessibilityHidden(true)
    }

    private var menuImage: NSImage {
        let source: NSImage?
        let template: Bool
        if name == "agents" {
            source = NSImage(named: "LogoSkillsSh")
            template = true
        } else if let host = SkillHost(agent: name) {
            source = NSImage(named: NSImage.Name(host.assetName))
            template = host.usesTemplateRendering
        } else {
            source = NSImage(
                systemSymbolName: toolFallbackSymbol(name),
                accessibilityDescription: nil
            )
            template = true
        }

        let image = (source?.copy() as? NSImage) ?? NSImage(size: NSSize(width: 16, height: 16))
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = template
        return image
    }
}

struct ToolMenuIconCluster: View {
    let toolNames: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(toolNames.prefix(3)), id: \.self) { name in
                ToolMenuIcon(name: name)
            }
        }
        .accessibilityHidden(true)
    }
}

private func toolFallbackSymbol(_ name: String) -> String {
    switch name {
    case "factory": "building.2"
    case "continue": "arrow.forward"
    case "kilocode": "k.square"
    case "crush": "heart"
    case "goose": "bird"
    case "roo": "hare"
    case "openclaw": "pawprint"
    case "pi": "function"
    default: "terminal"
    }
}

struct ToolLogo: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        ToolMark(name: name, size: size - 4)
            .padding(2)
            .frame(width: size, height: size)
            .background(SkillbookTheme.surface(.four), in: Circle())
            .overlay { Circle().stroke(.quaternary) }
    }
}

struct ToolLogoCluster: View {
    let toolNames: [String]
    var size: CGFloat = 16
    var maximumVisible = 3
    var showsOverflowCount = false

    var body: some View {
        HStack(spacing: -4) {
            ForEach(Array(toolNames.prefix(maximumVisible)), id: \.self) { name in
                ToolLogo(name: name, size: size)
            }
            if showsOverflowCount, overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .frame(height: size)
                    .background(SkillbookTheme.surface(.four), in: Capsule())
                    .overlay { Capsule().stroke(.quaternary) }
                    .padding(.leading, 6)
            }
        }
        .frame(minWidth: size, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toolNames.isEmpty ? "No linked tools" : toolNames.joined(separator: ", "))
    }

    private var overflowCount: Int {
        max(0, toolNames.count - maximumVisible)
    }
}

struct SkillOriginLabel: View {
    let row: SkillRow
    var compact: Bool = true

    var body: some View {
        switch row.origin {
        case .skillsSh:
            HStack(spacing: 4) {
                Image("LogoSkillsSh")
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 10 : 12, height: compact ? 10 : 12)
                    .accessibilityHidden(true)
                Text("skills.sh")
                if !compact, !row.sourceLabel.isEmpty, row.sourceLabel != "npx skills" {
                    Text("·")
                    Text(row.sourceLabel)
                        .lineLimit(1)
                }
            }
            .font(compact ? .caption2 : .caption)
            .foregroundStyle(.tertiary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(compact ? "Installed with skills.sh" : "Installed with skills.sh from \(row.sourceLabel)")
        case .git:
            HStack(spacing: 4) {
                Image("LogoGitHub")
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 10 : 12, height: compact ? 10 : 12)
                    .accessibilityHidden(true)
                Text(row.sourceLabel)
                    .lineLimit(1)
            }
            .font(compact ? .caption2 : .caption)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Git \(row.sourceLabel)")
        case .local:
            EmptyView()
        }
    }
}

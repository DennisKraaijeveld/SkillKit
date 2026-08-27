import MarkdownEngine
import MarkdownEngineCodeBlocks

@MainActor
enum SkillbookMarkdownCodeStyle {
    static let highlighter: any SyntaxHighlighter = HighlighterSwiftBridge()
}

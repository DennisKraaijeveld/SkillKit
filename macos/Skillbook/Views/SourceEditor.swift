import AppKit
import SwiftUI

enum SourceEditorSyntax: Sendable {
    case plain
    case yaml
    case markdown
}

struct MarkdownEditorCommand: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(Int)
        case bold
        case italic
        case link
        case inlineCode
        case codeBlock
        case bulletList
        case numberedList
        case quote
    }

    let id = UUID()
    let kind: Kind
}

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var syntax: SourceEditorSyntax = .plain
    var command: MarkdownEditorCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, syntax: syntax)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = MarkdownTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.defaultParagraphStyle = Self.paragraphStyle
        textView.string = text
        textView.setAccessibilityLabel(syntax == .markdown ? "Markdown editor" : "Source editor")

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.highlightAll()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        textView.isEditable = isEditable

        if context.coordinator.syntax != syntax {
            context.coordinator.syntax = syntax
            textView.setAccessibilityLabel(syntax == .markdown ? "Markdown editor" : "Source editor")
            context.coordinator.highlightAll()
        }

        if textView.string != text {
            context.coordinator.isApplyingBinding = true
            textView.string = text
            context.coordinator.isApplyingBinding = false
            context.coordinator.highlightAll()
        }

        if let command, command.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.kind, to: textView)
        }
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        return style
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var syntax: SourceEditorSyntax
        weak var textView: MarkdownTextView?
        var lastCommandID: UUID?
        var isApplyingBinding = false
        private var pendingRange: NSRange?
        private var needsFullHighlight = false
        private let highlighter = SourceSyntaxHighlighter()

        init(text: Binding<String>, syntax: SourceEditorSyntax) {
            self.text = text
            self.syntax = syntax
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            let replacementLength = (replacementString as NSString?)?.length ?? 0
            pendingRange = NSRange(
                location: affectedCharRange.location,
                length: max(affectedCharRange.length, replacementLength)
            )
            if syntax == .markdown {
                let changed = replacementString ?? ""
                let removed = (textView.string as NSString).substring(with: affectedCharRange)
                needsFullHighlight = changed.contains("```")
                    || changed.contains("~~~")
                    || removed.contains("```")
                    || removed.contains("~~~")
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            if !isApplyingBinding, text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            highlighter.apply(
                syntax: syntax,
                to: textView,
                changedRange: needsFullHighlight ? nil : pendingRange
            )
            pendingRange = nil
            needsFullHighlight = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard syntax == .markdown, commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            return continueMarkdownPrefix(in: textView)
        }

        func highlightAll() {
            guard let textView else { return }
            highlighter.apply(syntax: syntax, to: textView, changedRange: nil)
        }

        func apply(_ kind: MarkdownEditorCommand.Kind, to textView: NSTextView) {
            guard syntax == .markdown, textView.isEditable else { return }
            switch kind {
            case let .heading(level):
                prefixLines(in: textView, kind: .heading(level))
            case .bold:
                wrapSelection(in: textView, prefix: "**", suffix: "**", placeholder: "bold text")
            case .italic:
                wrapSelection(in: textView, prefix: "_", suffix: "_", placeholder: "italic text")
            case .link:
                wrapSelection(in: textView, prefix: "[", suffix: "](https://)", placeholder: "link text")
            case .inlineCode:
                wrapSelection(in: textView, prefix: "`", suffix: "`", placeholder: "code")
            case .codeBlock:
                wrapSelection(in: textView, prefix: "```\n", suffix: "\n```", placeholder: "code")
            case .bulletList:
                prefixLines(in: textView, kind: .bulletList)
            case .numberedList:
                prefixLines(in: textView, kind: .numberedList)
            case .quote:
                prefixLines(in: textView, kind: .quote)
            }
            textView.window?.makeFirstResponder(textView)
        }

        private func wrapSelection(
            in textView: NSTextView,
            prefix: String,
            suffix: String,
            placeholder: String
        ) {
            let range = textView.selectedRange()
            let selected = range.length > 0
                ? (textView.string as NSString).substring(with: range)
                : placeholder
            let replacement = prefix + selected + suffix
            replace(range, with: replacement, in: textView)
            textView.setSelectedRange(
                NSRange(location: range.location + prefix.utf16.count, length: selected.utf16.count)
            )
        }

        private enum LinePrefix {
            case heading(Int)
            case bulletList
            case numberedList
            case quote
        }

        private func prefixLines(in textView: NSTextView, kind: LinePrefix) {
            let source = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let lineRange = source.lineRange(for: selectedRange)
            let selectedLines = source.substring(with: lineRange)
            let hasTrailingNewline = selectedLines.hasSuffix("\n")
            var lines = selectedLines.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if hasTrailingNewline, lines.last?.isEmpty == true { lines.removeLast() }

            var number = 1
            let transformed = lines.map { line in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
                let stripped = Self.strippingBlockPrefix(from: line)
                switch kind {
                case let .heading(level):
                    return String(repeating: "#", count: level) + " " + stripped
                case .bulletList:
                    return "- " + stripped
                case .numberedList:
                    defer { number += 1 }
                    return "\(number). " + stripped
                case .quote:
                    return "> " + stripped
                }
            }
            let replacement = transformed.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
            replace(lineRange, with: replacement, in: textView)
            textView.setSelectedRange(NSRange(location: lineRange.location, length: replacement.utf16.count))
        }

        private func continueMarkdownPrefix(in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            let source = textView.string as NSString
            let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
            let beforeCursorRange = NSRange(
                location: lineRange.location,
                length: max(0, selection.location - lineRange.location)
            )
            let line = source.substring(with: beforeCursorRange)
            guard let continuation = Self.continuation(for: line) else { return false }

            if line.trimmingCharacters(in: .whitespaces) == continuation.currentPrefix.trimmingCharacters(in: .whitespaces) {
                let prefixRange = NSRange(location: lineRange.location, length: line.utf16.count)
                replace(prefixRange, with: "", in: textView)
                textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
            } else {
                replace(selection, with: "\n" + continuation.nextPrefix, in: textView)
                textView.setSelectedRange(
                    NSRange(location: selection.location + continuation.nextPrefix.utf16.count + 1, length: 0)
                )
            }
            return true
        }

        private func replace(_ range: NSRange, with replacement: String, in textView: NSTextView) {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
        }

        private static func strippingBlockPrefix(from line: String) -> String {
            line.replacingOccurrences(
                of: #"^\s*(?:#{1,6}\s+|[-+*]\s+|\d+[.)]\s+|>\s*)"#,
                with: "",
                options: .regularExpression
            )
        }

        private static func continuation(for line: String) -> (currentPrefix: String, nextPrefix: String)? {
            let patterns = [
                (#"^(\s*[-+*]\s+)"#, false),
                (#"^(\s*>\s*)"#, false),
                (#"^(\s*)(\d+)([.)]\s+)"#, true),
            ]
            for (pattern, numbered) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let fullRange = NSRange(location: 0, length: line.utf16.count)
                guard let match = regex.firstMatch(in: line, range: fullRange) else { continue }
                let source = line as NSString
                let currentPrefix = source.substring(with: match.range(at: numbered ? 0 : 1))
                if numbered {
                    let indentation = source.substring(with: match.range(at: 1))
                    let number = Int(source.substring(with: match.range(at: 2))) ?? 0
                    let suffix = source.substring(with: match.range(at: 3))
                    return (currentPrefix, "\(indentation)\(number + 1)\(suffix)")
                }
                return (currentPrefix, currentPrefix)
            }
            return nil
        }
    }
}

@MainActor
final class MarkdownTextView: NSTextView {}

@MainActor
private final class SourceSyntaxHighlighter {
    private let heading = SourceSyntaxHighlighter.regex(#"^(#{1,6})(?:\s+)(.*)$"#)
    private let quote = SourceSyntaxHighlighter.regex(#"^\s*(>+)\s?"#)
    private let list = SourceSyntaxHighlighter.regex(#"^\s*(?:[-+*]|\d+[.)])\s+"#)
    private let checkbox = SourceSyntaxHighlighter.regex(#"\[[ xX]\]"#)
    private let link = SourceSyntaxHighlighter.regex(#"!?\[[^\]]*\]\([^\)]+\)"#)
    private let inlineCode = SourceSyntaxHighlighter.regex(#"`[^`\n]+`"#)
    private let strong = SourceSyntaxHighlighter.regex(#"(?:\*\*[^*\n]+\*\*|__[^_\n]+__)"#)
    private let emphasis = SourceSyntaxHighlighter.regex(#"(?:\*[^*\n]+\*|_[^_\n]+_)"#)
    private let yamlKey = SourceSyntaxHighlighter.regex(#"^([A-Za-z0-9_-]+)(:)"#)
    private let yamlComment = SourceSyntaxHighlighter.regex(#"\s(#.*)$"#)
    private let yamlString = SourceSyntaxHighlighter.regex(#"(?:\"[^\"\n]*\"|'[^'\n]*')"#)

    func apply(syntax: SourceEditorSyntax, to textView: NSTextView, changedRange: NSRange?) {
        guard let layoutManager = textView.layoutManager else { return }
        let source = textView.string as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        guard fullRange.length > 0 else { return }
        let targetRange = expandedLineRange(changedRange ?? fullRange, in: source)

        for attribute in [NSAttributedString.Key.foregroundColor, .font, .backgroundColor] {
            layoutManager.removeTemporaryAttribute(attribute, forCharacterRange: targetRange)
        }

        switch syntax {
        case .plain:
            break
        case .yaml:
            highlightYAML(source, range: targetRange, layoutManager: layoutManager)
        case .markdown:
            highlightMarkdown(source, range: targetRange, layoutManager: layoutManager)
        }
    }

    private func highlightMarkdown(
        _ source: NSString,
        range: NSRange,
        layoutManager: NSLayoutManager
    ) {
        var insideFence = fenceState(before: range.location, in: source)
        var location = range.location
        let rangeEnd = NSMaxRange(range)

        while location < rangeEnd {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = rangeWithoutLineEnding(lineRange, in: source)
            let line = source.substring(with: contentRange)
            let isFence = Self.isFence(line)

            if insideFence || isFence {
                layoutManager.addTemporaryAttributes(
                    [
                        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                        .foregroundColor: isFence ? NSColor.systemPurple : NSColor.secondaryLabelColor,
                        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.08),
                    ],
                    forCharacterRange: contentRange
                )
                if isFence { insideFence.toggle() }
            } else {
                highlightMarkdownLine(line, absoluteRange: contentRange, layoutManager: layoutManager)
            }

            let next = NSMaxRange(lineRange)
            if next <= location { break }
            location = next
        }
    }

    private func highlightMarkdownLine(
        _ line: String,
        absoluteRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        let localRange = NSRange(location: 0, length: line.utf16.count)
        if let match = heading.firstMatch(in: line, range: localRange) {
            let level = match.range(at: 1).length
            let size: CGFloat = switch level {
            case 1: 21
            case 2: 18
            case 3: 16
            default: 14
            }
            layoutManager.addTemporaryAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: size, weight: level <= 2 ? .semibold : .medium),
                forCharacterRange: absoluteRange
            )
            add(
                [.foregroundColor: NSColor.tertiaryLabelColor],
                match.range(at: 1),
                offset: absoluteRange.location,
                to: layoutManager
            )
        }

        addMatches(quote, in: line, range: localRange, attributes: [.foregroundColor: NSColor.systemBlue], offset: absoluteRange.location, to: layoutManager)
        addMatches(list, in: line, range: localRange, attributes: [.foregroundColor: NSColor.systemBlue], offset: absoluteRange.location, to: layoutManager)
        addMatches(checkbox, in: line, range: localRange, attributes: [.foregroundColor: NSColor.systemGreen], offset: absoluteRange.location, to: layoutManager)
        addMatches(link, in: line, range: localRange, attributes: [.foregroundColor: NSColor.linkColor], offset: absoluteRange.location, to: layoutManager)
        addMatches(
            inlineCode,
            in: line,
            range: localRange,
            attributes: [
                .foregroundColor: NSColor.systemPurple,
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.1),
            ],
            offset: absoluteRange.location,
            to: layoutManager
        )
        addMatches(
            strong,
            in: line,
            range: localRange,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)],
            offset: absoluteRange.location,
            to: layoutManager
        )
        addMatches(
            emphasis,
            in: line,
            range: localRange,
            attributes: [.font: NSFontManager.shared.convert(
                NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                toHaveTrait: .italicFontMask
            )],
            offset: absoluteRange.location,
            to: layoutManager
        )
    }

    private func highlightYAML(
        _ source: NSString,
        range: NSRange,
        layoutManager: NSLayoutManager
    ) {
        let text = source.substring(with: range)
        let localRange = NSRange(location: 0, length: text.utf16.count)
        addMatches(yamlKey, in: text, range: localRange, capture: 1, attributes: [.foregroundColor: NSColor.systemBlue], offset: range.location, to: layoutManager)
        addMatches(yamlComment, in: text, range: localRange, capture: 1, attributes: [.foregroundColor: NSColor.tertiaryLabelColor], offset: range.location, to: layoutManager)
        addMatches(yamlString, in: text, range: localRange, attributes: [.foregroundColor: NSColor.systemRed], offset: range.location, to: layoutManager)
    }

    private func addMatches(
        _ regex: NSRegularExpression,
        in string: String,
        range: NSRange,
        capture: Int = 0,
        attributes: [NSAttributedString.Key: Any],
        offset: Int,
        to layoutManager: NSLayoutManager
    ) {
        regex.enumerateMatches(in: string, range: range) { match, _, _ in
            guard let match else { return }
            add(attributes, match.range(at: capture), offset: offset, to: layoutManager)
        }
    }

    private func add(
        _ attributes: [NSAttributedString.Key: Any],
        _ range: NSRange,
        offset: Int,
        to layoutManager: NSLayoutManager
    ) {
        guard range.location != NSNotFound else { return }
        layoutManager.addTemporaryAttributes(
            attributes,
            forCharacterRange: NSRange(location: range.location + offset, length: range.length)
        )
    }

    private func expandedLineRange(_ range: NSRange, in source: NSString) -> NSRange {
        let start = max(0, range.location - 1)
        let end = min(source.length, NSMaxRange(range) + 1)
        return source.lineRange(for: NSRange(location: start, length: max(0, end - start)))
    }

    private func rangeWithoutLineEnding(_ range: NSRange, in source: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let character = source.character(at: range.location + length - 1)
            guard character == 10 || character == 13 else { break }
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    private func fenceState(before location: Int, in source: NSString) -> Bool {
        guard location > 0 else { return false }
        var insideFence = false
        var cursor = 0
        while cursor < location {
            let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
            if Self.isFence(source.substring(with: rangeWithoutLineEnding(lineRange, in: source))) {
                insideFence.toggle()
            }
            let next = NSMaxRange(lineRange)
            if next <= cursor { break }
            cursor = next
        }
        return insideFence
    }

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            preconditionFailure("Invalid syntax highlighting expression")
        }
        return expression
    }
}

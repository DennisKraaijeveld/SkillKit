import Foundation
import Markdown
import MarkdownEngine

enum MarkdownLinkDestination: Equatable, Sendable {
    case skillDocument(URL)
    case section(String)
    case external(URL)

    static func resolve(
        _ destination: URL,
        relativeTo documentDirectory: URL,
        within skillFolder: URL? = nil
    ) -> MarkdownLinkDestination {
        if destination.relativeString.hasPrefix("#") {
            return .section(String(destination.relativeString.dropFirst()))
        }
        guard destination.scheme == nil || destination.isFileURL else {
            return .external(destination)
        }

        let components = URLComponents(
            url: destination,
            resolvingAgainstBaseURL: false
        )
        let relativePath = components?.percentEncodedPath.removingPercentEncoding
            ?? destination.path
        var fileURL = (destination.isFileURL || relativePath.hasPrefix("/"))
            ? URL(fileURLWithPath: relativePath)
            : documentDirectory.appendingPathComponent(relativePath)
        fileURL = fileURL
            .standardizedFileURL
            .resolvingSymlinksInPath()

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            fileURL = fileURL
                .appendingPathComponent("README.md")
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }
        let isMarkdown = ["md", "markdown"].contains(fileURL.pathExtension.lowercased())
        guard isMarkdown, contains(fileURL, within: skillFolder ?? documentDirectory) else {
            return .external(destination)
        }

        var resolvedComponents = URLComponents(
            url: fileURL,
            resolvingAgainstBaseURL: false
        )
        resolvedComponents?.fragment = components?.fragment
        return .skillDocument(resolvedComponents?.url ?? fileURL)
    }

    static func contains(_ fileURL: URL, within skillFolder: URL) -> Bool {
        let resolvedFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedRoot = skillFolder.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        return resolvedFile.path == resolvedRoot.path || resolvedFile.path.hasPrefix(rootPath)
    }
}

enum MarkdownReaderLinks {
    private static let internalPrefix = "skillbook-internal:"
    private static let pathPrefix = "skillbook-path:"

    static func source(
        _ source: String,
        documentURL: URL,
        skillFolder: URL
    ) -> String {
        let sourceString = source as NSString
        let sourceMap = MarkdownSourceMap(source: source)
        var links = MarkdownLinkCollector()
        links.visit(Document(parsing: source))
        guard !links.links.isEmpty || !links.inlineCodes.isEmpty else { return source }

        let result = NSMutableString(string: source)
        var replacements = links.links.compactMap { link -> MarkdownLinkReplacement? in
            guard let rawDestination = link.destination else { return nil }
            return MarkdownLinkReplacement(
                range: sourceMap.nsRange(for: link.range),
                label: link.plainText,
                destination: rawDestination,
                prefix: internalPrefix
            )
        }
        replacements.append(contentsOf: links.inlineCodes.compactMap { inlineCode in
            let rawDestination = inlineCode.code
            guard
                let destination = URL(string: rawDestination),
                case let .skillDocument(fileURL) = MarkdownLinkDestination.resolve(
                    destination,
                    relativeTo: documentURL.deletingLastPathComponent(),
                    within: skillFolder
                ),
                FileManager.default.fileExists(atPath: fileURL.path)
            else { return nil }
            return MarkdownLinkReplacement(
                range: sourceMap.nsRange(for: inlineCode.range),
                label: rawDestination,
                destination: rawDestination,
                prefix: pathPrefix
            )
        })

        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            guard
                replacement.range.length > 0,
                NSMaxRange(replacement.range) <= sourceString.length,
                !replacement.label.contains("|"),
                !replacement.label.contains("]"),
                let destination = URL(string: replacement.destination)
            else { continue }
            let resolved = MarkdownLinkDestination.resolve(
                destination,
                relativeTo: documentURL.deletingLastPathComponent(),
                within: skillFolder
            )
            switch resolved {
            case .skillDocument, .section:
                let encoded = Data(replacement.destination.utf8).base64EncodedString()
                result.replaceCharacters(
                    in: replacement.range,
                    with: "[[\(replacement.label)|\(replacement.prefix)\(encoded)]]"
                )
            case .external:
                continue
            }
        }
        return result as String
    }

    static func destination(from identifier: String) -> String? {
        let prefix: String
        if identifier.hasPrefix(internalPrefix) {
            prefix = internalPrefix
        } else if identifier.hasPrefix(pathPrefix) {
            prefix = pathPrefix
        } else {
            return nil
        }
        let encoded = String(identifier.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func storageSource(_ source: String) -> String {
        let pattern = #"\[\[([^\]\n|]+)\|(skillbook-(internal|path):[A-Za-z0-9+/=]+)\]\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return source
        }

        let sourceString = source as NSString
        let result = NSMutableString(string: source)
        let matches = expression.matches(
            in: source,
            range: NSRange(location: 0, length: sourceString.length)
        )
        for match in matches.reversed() {
            guard
                match.numberOfRanges == 4,
                let destination = destination(
                    from: sourceString.substring(with: match.range(at: 2))
                )
            else { continue }
            let label = sourceString.substring(with: match.range(at: 1))
            let replacement = sourceString.substring(with: match.range(at: 3)) == "path"
                ? "`\(label)`"
                : "[\(label)](\(destination))"
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }
}

private struct MarkdownLinkCollector: MarkupWalker {
    var links: [Markdown.Link] = []
    var inlineCodes: [Markdown.InlineCode] = []

    mutating func visitLink(_ link: Markdown.Link) {
        links.append(link)
    }

    mutating func visitInlineCode(_ inlineCode: Markdown.InlineCode) {
        inlineCodes.append(inlineCode)
    }
}

struct SkillbookMarkdownLinkResolver: WikiLinkResolver {
    func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
        guard MarkdownReaderLinks.destination(from: displayName) != nil else { return nil }
        return WikiLinkResolution(id: displayName, exists: true)
    }

    func fingerprint() -> AnyHashable {
        "skillbook-internal-links-v1"
    }
}

private struct MarkdownLinkReplacement {
    let range: NSRange
    let label: String
    let destination: String
    let prefix: String
}

struct MarkdownContent: Sendable {
    let source: String
    let blocks: [MarkdownBlock]
    let outline: [MarkdownOutlineItem]
    let wordCount: Int

    static let empty = MarkdownContent(source: "", blocks: [], outline: [], wordCount: 0)

    init(source: String) {
        var builder = MarkdownContentBuilder(source: source)
        let document = Document(parsing: source)
        let blocks = document.blockChildren.enumerated().compactMap { index, markup in
            builder.block(from: markup, path: "\(index)", includeInOutline: true)
        }

        self.source = source
        self.blocks = blocks
        self.outline = Self.addPreviews(to: builder.outline, source: source)
        self.wordCount = source.split { character in
            character.isWhitespace || character.isPunctuation
        }.count
    }

    private init(source: String, blocks: [MarkdownBlock], outline: [MarkdownOutlineItem], wordCount: Int) {
        self.source = source
        self.blocks = blocks
        self.outline = outline
        self.wordCount = wordCount
    }

    func blocks(hidingDuplicateTitle title: String?) -> [MarkdownBlock] {
        guard hidesFirstHeading(matching: title) else { return blocks }
        return Array(blocks.dropFirst())
    }

    func outline(hidingDuplicateTitle title: String?) -> [MarkdownOutlineItem] {
        guard hidesFirstHeading(matching: title), let first = blocks.first else { return outline }
        return outline.filter { $0.id != first.id }
    }

    private func hidesFirstHeading(matching title: String?) -> Bool {
        guard
            let title,
            let first = blocks.first,
            case let .heading(level, _, plainText) = first.kind,
            level == 1
        else {
            return false
        }
        return Self.normalizedTitle(plainText) == Self.normalizedTitle(title)
    }

    private static func normalizedTitle(_ title: String) -> String {
        String(title.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func addPreviews(
        to items: [MarkdownOutlineItem],
        source: String
    ) -> [MarkdownOutlineItem] {
        let sourceLength = (source as NSString).length
        return items.enumerated().map { index, item in
            let start = min(NSMaxRange(item.sourceRange), sourceLength)
            let end = min(
                index + 1 < items.count ? items[index + 1].sourceRange.location : sourceLength,
                sourceLength
            )
            let range = NSRange(location: start, length: max(0, end - start))
            let section = (source as NSString).substring(with: range)
            return MarkdownOutlineItem(
                id: item.id,
                level: item.level,
                title: item.title,
                preview: previewText(from: section),
                sourceRange: item.sourceRange
            )
        }
    }

    private static func previewText(from section: String) -> String {
        let lines = section
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix(String(repeating: "\u{60}", count: 3))
                    && line.range(
                        of: #"^\|?\s*:?-{3,}"#,
                        options: .regularExpression
                    ) == nil
            }
            .prefix(3)

        var preview = lines.joined(separator: " ")
        preview = preview.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        preview = preview.replacingOccurrences(
            of: #"^[>\-+*\d.\)\s]+"#,
            with: "",
            options: .regularExpression
        )
        preview = preview.replacingOccurrences(
            of: #"[\x60*_~]"#,
            with: "",
            options: .regularExpression
        )
        guard preview.count > 180 else { return preview }
        return String(preview.prefix(177)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

struct MarkdownOutlineItem: Identifiable, Sendable {
    let id: String
    let level: Int
    let title: String
    let preview: String
    let sourceRange: NSRange
}

struct MarkdownBlock: Identifiable, Sendable {
    indirect enum Kind: Sendable {
        case paragraph(AttributedString)
        case heading(level: Int, text: AttributedString, plainText: String)
        case code(language: String?, text: String)
        case quote([MarkdownBlock])
        case unordered([MarkdownListItem])
        case ordered(start: Int, items: [MarkdownListItem])
        case rule
        case table(MarkdownTable)
        case image(MarkdownImage)
        case raw(String)
    }

    let id: String
    let kind: Kind
}

struct MarkdownListItem: Identifiable, Sendable {
    let id: String
    let checkbox: Bool?
    let blocks: [MarkdownBlock]
}

struct MarkdownTable: Sendable {
    let header: [AttributedString]
    let rows: [[AttributedString]]
    let alignments: [MarkdownTableAlignment]
}

enum MarkdownTableAlignment: Sendable {
    case leading
    case center
    case trailing
}

struct MarkdownImage: Sendable {
    let source: String
    let alt: String
    let title: String?
}

private struct MarkdownContentBuilder {
    var outline: [MarkdownOutlineItem] = []
    private let sourceMap: MarkdownSourceMap
    private var usedSlugs: [String: Int] = [:]

    init(source: String) {
        sourceMap = MarkdownSourceMap(source: source)
    }

    mutating func block(
        from markup: BlockMarkup,
        path: String,
        includeInOutline: Bool
    ) -> MarkdownBlock? {
        if let heading = markup as? Heading {
            let slug = uniqueSlug(heading.plainText)
            let id = includeInOutline ? slug : "block-\(path)"
            if includeInOutline {
                outline.append(
                    MarkdownOutlineItem(
                        id: id,
                        level: heading.level,
                        title: heading.plainText,
                        preview: "",
                        sourceRange: sourceMap.nsRange(for: heading.range)
                    )
                )
            }
            return MarkdownBlock(
                id: id,
                kind: .heading(
                    level: heading.level,
                    text: Self.attributedText(from: heading),
                    plainText: heading.plainText
                )
            )
        }

        if let paragraph = markup as? Paragraph {
            if
                paragraph.childCount == 1,
                let image = paragraph.child(at: 0) as? Markdown.Image,
                let source = image.source
            {
                return MarkdownBlock(
                    id: "block-\(path)",
                    kind: .image(
                        MarkdownImage(source: source, alt: image.plainText, title: image.title)
                    )
                )
            }
            return MarkdownBlock(id: "block-\(path)", kind: .paragraph(Self.attributedText(from: paragraph)))
        }

        if let code = markup as? CodeBlock {
            return MarkdownBlock(
                id: "block-\(path)",
                kind: .code(language: code.language, text: code.code)
            )
        }

        if let quote = markup as? BlockQuote {
            let children = quote.blockChildren.enumerated().compactMap { index, child in
                block(from: child, path: "\(path)-\(index)", includeInOutline: false)
            }
            return MarkdownBlock(id: "block-\(path)", kind: .quote(children))
        }

        if let list = markup as? UnorderedList {
            return MarkdownBlock(
                id: "block-\(path)",
                kind: .unordered(listItems(from: list.listItems, path: path))
            )
        }

        if let list = markup as? OrderedList {
            return MarkdownBlock(
                id: "block-\(path)",
                kind: .ordered(
                    start: Int(list.startIndex),
                    items: listItems(from: list.listItems, path: path)
                )
            )
        }

        if markup is ThematicBreak {
            return MarkdownBlock(id: "block-\(path)", kind: .rule)
        }

        if let table = markup as? Table {
            let header = Array(table.head.cells.map { Self.attributedText(from: $0) })
            let rows = Array(table.body.rows.map { row in
                Array(row.cells.map { Self.attributedText(from: $0) })
            })
            let alignments: [MarkdownTableAlignment] = table.columnAlignments.map { alignment in
                switch alignment {
                case .some(.center): .center
                case .some(.right): .trailing
                default: .leading
            }
            }
            return MarkdownBlock(
                id: "block-\(path)",
                kind: .table(MarkdownTable(header: header, rows: rows, alignments: alignments))
            )
        }

        if let html = markup as? HTMLBlock {
            return MarkdownBlock(id: "block-\(path)", kind: .raw(html.rawHTML))
        }

        return MarkdownBlock(id: "block-\(path)", kind: .raw(markup.format()))
    }

    private mutating func listItems<Items: Sequence>(
        from items: Items,
        path: String
    ) -> [MarkdownListItem] where Items.Element == ListItem {
        items.enumerated().map { index, item in
            let blocks = item.blockChildren.enumerated().compactMap { childIndex, child in
                block(
                    from: child,
                    path: "\(path)-\(index)-\(childIndex)",
                    includeInOutline: false
                )
            }
            let checkbox: Bool? = switch item.checkbox {
            case .checked: true
            case .unchecked: false
            case nil: nil
            }
            return MarkdownListItem(id: "item-\(path)-\(index)", checkbox: checkbox, blocks: blocks)
        }
    }

    private static func attributedText(from container: some InlineContainer) -> AttributedString {
        let source = container.inlineChildren.reduce(into: "") { result, child in
            result += child.format()
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(container.plainText)
    }

    private mutating func uniqueSlug(_ text: String) -> String {
        let normalized = String(text
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            })
        var slug = normalized
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        if slug.isEmpty { slug = "heading" }
        let count = usedSlugs[slug, default: 0]
        usedSlugs[slug] = count + 1
        return count == 0 ? slug : "\(slug)-\(count + 1)"
    }
}

private struct MarkdownSourceMap {
    private let lines: [Substring]
    private let lineUTF16Offsets: [Int]
    private let sourceLength: Int

    init(source: String) {
        lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        sourceLength = (source as NSString).length

        var offsets: [Int] = []
        var offset = 0
        for line in lines {
            offsets.append(offset)
            offset += line.utf16.count + 1
        }
        lineUTF16Offsets = offsets
    }

    func nsRange(for range: SourceRange?) -> NSRange {
        guard let range else { return NSRange(location: 0, length: 0) }
        let lower = utf16Offset(for: range.lowerBound)
        let upper = utf16Offset(for: range.upperBound)
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    private func utf16Offset(for location: SourceLocation) -> Int {
        let lineIndex = min(max(location.line - 1, 0), max(lines.count - 1, 0))
        guard lines.indices.contains(lineIndex), lineUTF16Offsets.indices.contains(lineIndex) else {
            return sourceLength
        }
        let line = lines[lineIndex]
        let byteOffset = min(max(location.column - 1, 0), line.utf8.count)
        let prefix = String(decoding: line.utf8.prefix(byteOffset), as: UTF8.self)
        return min(lineUTF16Offsets[lineIndex] + prefix.utf16.count, sourceLength)
    }
}

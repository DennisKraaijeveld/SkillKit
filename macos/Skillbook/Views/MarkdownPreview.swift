import AppKit
import MarkdownEngine
import os
import SwiftUI

private struct MarkdownReaderRequest: Hashable, Sendable {
    let documentID: String
    let source: String
}

private struct MarkdownReaderDocument: Hashable, Sendable {
    let fileURL: URL
    let source: String
    let title: String
    let initialHeadingID: String?
}

private actor MarkdownContentParser {
    func parse(_ request: MarkdownReaderRequest) -> MarkdownContent? {
        guard !Task.isCancelled else { return nil }
        let parsed = MarkdownContent(source: request.source)
        return Task.isCancelled ? nil : parsed
    }
}

private enum ReaderNavigation {
    static let request = Notification.Name("com.denniskraaijeveld.skillkit.reader.heading")

    static func jump(to headingID: String, documentID: String) {
        NotificationCenter.default.post(
            name: request,
            object: nil,
            userInfo: ["headingID": headingID, "documentID": documentID]
        )
    }
}

enum ReaderScrollGeometry {
    static func scrollOriginY(
        fragmentMinY: CGFloat,
        textViewMinY: CGFloat,
        textContainerOriginY: CGFloat,
        contentInsetTop: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        fragmentMinY
            + textViewMinY
            + textContainerOriginY
            - contentInsetTop
            - viewportHeight * 0.18
    }

    static func textContainerY(
        scrollOriginY: CGFloat,
        viewportHeight: CGFloat,
        textViewMinY: CGFloat,
        textContainerOriginY: CGFloat
    ) -> CGFloat {
        scrollOriginY
            + viewportHeight * 0.2
            - textViewMinY
            - textContainerOriginY
    }
}

struct ReaderNavigationGate {
    private(set) var generation = 0
    private(set) var isActive = false

    mutating func begin() -> Int {
        generation &+= 1
        isActive = true
        return generation
    }

    mutating func finish(_ generation: Int) -> Bool {
        guard self.generation == generation else { return false }
        isActive = false
        return true
    }
}

struct MarkdownPreview: View {
    private static let parser = MarkdownContentParser()

    @Environment(AppModel.self) private var model
    @State private var content = MarkdownContent.empty
    @State private var activeHeadingID: String?
    @State private var referenceDocuments: [MarkdownReaderDocument] = []

    var body: some View {
        let skill = model.selected
        let rootDocument = MarkdownReaderDocument(
            fileURL: URL(fileURLWithPath: skill?.skillMd ?? "/dev/null"),
            source: model.bodyText,
            title: skill?.name ?? "Untitled",
            initialHeadingID: nil
        )
        let document = referenceDocuments.last ?? rootDocument
        let skillFolder = URL(fileURLWithPath: skill?.folder ?? "/dev/null", isDirectory: true)
        let readerSource = MarkdownReaderLinks.source(
            document.source,
            documentURL: document.fileURL,
            skillFolder: skillFolder
        )
        let documentID = "reader-\(document.fileURL.path)"
        let duplicateTitle = referenceDocuments.isEmpty ? skill?.name : nil
        let headings = Self.navigationHeadings(
            from: content.outline(hidingDuplicateTitle: duplicateTitle)
        )
        let request = MarkdownReaderRequest(
            documentID: documentID,
            source: readerSource
        )

        ZStack(alignment: .leading) {
            NativeTextViewWrapper(
                text: .constant(readerSource),
                configuration: configuration,
                fontName: "SF Pro",
                fontSize: 15,
                documentId: documentID,
                isEditable: false,
                onLinkClick: { identifier in
                    openLink(
                        identifier,
                        from: document,
                        skillFolder: skillFolder,
                        documentID: documentID
                    )
                },
                placeholder: NSAttributedString(
                    string: "No instructions yet",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 15),
                        .foregroundColor: NSColor.placeholderTextColor,
                    ]
                ),
                header: AnyView(readerHeader(document: document, skill: skill)),
                headerCollapsedHeight: 0,
                headerExpanded: true,
                onPersistScrollOffset: { id, offset in
                    model.markdownReaderOffsets[id] = offset
                },
                restoreScrollOffset: { id in
                    model.markdownReaderOffsets[id]
                }
            )

            ReaderScrollTracker(
                source: readerSource,
                headings: headings,
                documentID: documentID,
                activeHeadingID: $activeHeadingID
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)

            if headings.count > 1 {
                ReaderHeadingRail(
                    headings: headings,
                    activeHeadingID: activeHeadingID,
                    documentID: documentID
                )
                .padding(.leading, 6)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: SkillbookTheme.articleMaxWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SkillbookTheme.surface(.one))
        .task(id: request) {
            let signposter = SkillbookSignposts.rendering
            let signpostState = signposter.beginInterval("Markdown Parse")
            let parsed = await Self.parser.parse(request)
            signposter.endInterval("Markdown Parse", signpostState)
            guard let parsed, !Task.isCancelled else { return }
            content = parsed

            let parsedHeadings = Self.navigationHeadings(
                from: parsed.outline(hidingDuplicateTitle: duplicateTitle)
            )
            let ids = Set(parsedHeadings.map(\.id))
            if activeHeadingID == nil || !ids.contains(activeHeadingID ?? "") {
                activeHeadingID = parsedHeadings.first?.id
            }
            if let headingID = document.initialHeadingID {
                ReaderNavigation.jump(to: headingID, documentID: documentID)
            }
        }
        .task(id: model.pendingMarkdownReaderLink) {
            guard let rawDestination = model.pendingMarkdownReaderLink else { return }
            model.pendingMarkdownReaderLink = nil
            openLink(
                rawDestination: rawDestination,
                from: rootDocument,
                skillFolder: skillFolder,
                documentID: documentID
            )
        }
    }

    private static func navigationHeadings(
        from outline: [MarkdownOutlineItem]
    ) -> [MarkdownOutlineItem] {
        let majorSections = outline.filter { $0.level <= 2 }
        return majorSections.count > 1 ? majorSections : outline
    }

    private var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.wikiLinks = SkillbookMarkdownLinkResolver()
        configuration.services.syntaxHighlighter = SkillbookMarkdownCodeStyle.highlighter
        configuration.extensions = [StrikethroughExtension()]
        configuration.textInsets = TextInsets(
            horizontal: 50,
            vertical: 18
        )
        configuration.headings = HeadingStyle(
            fontMultipliers: [1.7, 1.4, 1.2, 1.08, 1, 0.92],
            topSpacingEm: [0.32, 0.28, 0.24, 0.2, 0.16, 0.12]
        )
        configuration.paragraph = ParagraphStyle(spacingFactor: 0.28, lineHeightExtraSpacing: 2)
        configuration.overscroll = OverscrollPolicy(percent: 0.28, maxPoints: 260, minPoints: 40)
        return configuration
    }

    private func readerHeader(document: MarkdownReaderDocument, skill: SkillRow?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if !referenceDocuments.isEmpty {
                    Button {
                        referenceDocuments.removeLast()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .help("Back to the previous document")
                }

                Text(document.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }

            if referenceDocuments.isEmpty, let description = skill?.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .padding(.top, 8)
            }

            if let skill {
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ToolLogoCluster(toolNames: skill.toolNames, size: 18)
                        SkillOriginLabel(row: skill, compact: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Divider()
                        .frame(height: 14)

                    Text(document.fileURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(document.fileURL.path)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if referenceDocuments.isEmpty {
                        SkillLocationsButton(skill: skill)
                            .fixedSize()
                    }
                }
                .frame(minHeight: 20)
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .skillbookSurface(.three, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func openLink(
        _ identifier: String,
        from document: MarkdownReaderDocument,
        skillFolder: URL,
        documentID: String
    ) {
        guard
            let rawDestination = MarkdownReaderLinks.destination(from: identifier),
            !rawDestination.isEmpty
        else { return }
        openLink(
            rawDestination: rawDestination,
            from: document,
            skillFolder: skillFolder,
            documentID: documentID
        )
    }

    private func openLink(
        rawDestination: String,
        from document: MarkdownReaderDocument,
        skillFolder: URL,
        documentID: String
    ) {
        guard let destinationURL = URL(string: rawDestination) else { return }
        let destination = MarkdownLinkDestination.resolve(
            destinationURL,
            relativeTo: document.fileURL.deletingLastPathComponent(),
            within: skillFolder
        )
        switch destination {
        case let .section(headingID):
            ReaderNavigation.jump(to: headingID, documentID: documentID)
        case let .skillDocument(fileURL):
            openDocument(fileURL, skillFolder: skillFolder)
        case .external:
            return
        }
    }

    private func openDocument(_ destination: URL, skillFolder: URL) {
        let fileURL = URL(fileURLWithPath: destination.path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard MarkdownLinkDestination.contains(fileURL, within: skillFolder) else { return }
        let headingID = destination.fragment

        Task {
            do {
                let source = try await Task.detached {
                    try String(contentsOf: fileURL, encoding: .utf8)
                }.value
                let parsed = await Self.parser.parse(
                    MarkdownReaderRequest(documentID: fileURL.path, source: source)
                )
                let title = parsed?.outline.first(where: { $0.level == 1 })?.title
                    ?? fileURL.deletingPathExtension().lastPathComponent
                referenceDocuments.append(
                    MarkdownReaderDocument(
                        fileURL: fileURL,
                        source: source,
                        title: title,
                        initialHeadingID: headingID
                    )
                )
            } catch {
                model.error = "Could not open \(fileURL.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

}

private struct ReaderHeadingRail: View {
    let headings: [MarkdownOutlineItem]
    let activeHeadingID: String?
    let documentID: String
    @State private var pointerY: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let metrics = RailMetrics(height: proxy.size.height, count: headings.count)

            ZStack(alignment: .topLeading) {
                ForEach(Array(headings.enumerated()), id: \.element.id) { index, heading in
                    let centerY = metrics.centerY(for: index)
                    Button {
                        ReaderNavigation.jump(to: heading.id, documentID: documentID)
                    } label: {
                        Capsule()
                            .fill(markerColor(for: heading, centerY: centerY))
                            .frame(width: markerWidth(for: heading, centerY: centerY), height: 3)
                            .frame(width: 28, height: metrics.hitHeight, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: 14, y: centerY)
                    .accessibilityLabel("Jump to \(heading.title)")
                    .accessibilityAddTraits(
                        heading.id == activeHeadingID ? .isSelected : []
                    )
                }
            }
            .frame(width: 28, height: proxy.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    pointerY = metrics.contains(location.y) ? location.y : nil
                case .ended:
                    pointerY = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if
                    let pointerY,
                    let hoveredHeading = hoveredHeading(at: pointerY, metrics: metrics)
                {
                    ReaderHeadingPreview(heading: hoveredHeading)
                        .offset(x: 36, y: metrics.previewTop(for: pointerY))
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.97, anchor: .leading)
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.82), value: pointerY)
        }
        .frame(width: 28)
        .zIndex(10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document sections")
    }

    private func hoveredHeading(
        at pointerY: CGFloat,
        metrics: RailMetrics
    ) -> MarkdownOutlineItem? {
        guard !headings.isEmpty else { return nil }
        return headings[metrics.nearestIndex(to: pointerY)]
    }

    private func markerWidth(for heading: MarkdownOutlineItem, centerY: CGFloat) -> CGFloat {
        let baseWidth: CGFloat = switch heading.level {
        case 1: 14
        case 2: 10
        default: 8
        }
        let activeExpansion: CGFloat = heading.id == activeHeadingID ? 5 : 0
        guard let pointerY else { return baseWidth + activeExpansion }
        let proximity = max(0, 1 - abs(pointerY - centerY) / 36)
        return baseWidth + activeExpansion + 8 * proximity
    }

    private func markerColor(for heading: MarkdownOutlineItem, centerY: CGFloat) -> Color {
        if heading.id == activeHeadingID { return .primary.opacity(0.82) }
        guard let pointerY else { return .secondary.opacity(0.28) }
        let proximity = max(0, 1 - abs(pointerY - centerY) / 36)
        return .secondary.opacity(0.28 + 0.42 * proximity)
    }

    private struct RailMetrics {
        let height: CGFloat
        let count: Int

        var step: CGFloat {
            guard count > 1 else { return 13 }
            return min(14, max(11, (height - 28) / CGFloat(count - 1)))
        }

        var hitHeight: CGFloat { max(11, step) }

        private var contentHeight: CGFloat {
            CGFloat(max(0, count - 1)) * step
        }

        private var startY: CGFloat {
            max(14, (height - contentHeight) / 2)
        }

        func centerY(for index: Int) -> CGFloat {
            startY + CGFloat(index) * step
        }

        func nearestIndex(to y: CGFloat) -> Int {
            guard count > 1 else { return 0 }
            let rawIndex = ((y - startY) / step).rounded()
            return min(count - 1, max(0, Int(rawIndex)))
        }

        func contains(_ y: CGFloat) -> Bool {
            y >= startY - hitHeight / 2
                && y <= centerY(for: max(0, count - 1)) + hitHeight / 2
        }

        func previewTop(for pointerY: CGFloat) -> CGFloat {
            min(max(10, pointerY - 48), max(10, height - 126))
        }
    }
}

private struct ReaderHeadingPreview: View {
    let heading: MarkdownOutlineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !heading.preview.isEmpty {
                Text(heading.preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 280)
        .skillbookSurface(.seven, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ReaderScrollTracker: NSViewRepresentable {
    let source: String
    let headings: [MarkdownOutlineItem]
    let documentID: String
    @Binding var activeHeadingID: String?

    func makeNSView(context: Context) -> ReaderScrollTrackingView {
        let view = ReaderScrollTrackingView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ReaderScrollTrackingView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: ReaderScrollTrackingView) {
        view.configure(
            source: source,
            headings: headings,
            documentID: documentID,
            onActiveHeadingChange: { headingID in
                if activeHeadingID != headingID {
                    activeHeadingID = headingID
                }
            }
        )
    }
}

@MainActor
private final class ReaderScrollTrackingView: NSView {
    private var source = ""
    private var headings: [MarkdownOutlineItem] = []
    private var documentID = ""
    private var headingSignature: [String] = []
    private var onActiveHeadingChange: (String?) -> Void = { _ in }
    private weak var textView: NSTextView?
    private weak var clipView: NSClipView?
    private var navigationGate = ReaderNavigationGate()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleAttachment()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            NotificationCenter.default.removeObserver(self)
            textView = nil
            clipView = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func configure(
        source: String,
        headings: [MarkdownOutlineItem],
        documentID: String,
        onActiveHeadingChange: @escaping (String?) -> Void
    ) {
        let signature = headings.map { "\($0.id):\($0.sourceRange.location)" }
        let needsAttachment = self.source != source
            || self.documentID != documentID
            || headingSignature != signature

        self.source = source
        self.headings = headings
        self.documentID = documentID
        self.onActiveHeadingChange = onActiveHeadingChange
        headingSignature = signature

        if needsAttachment {
            scheduleAttachment()
        } else if !navigationGate.isActive {
            updateActiveHeading()
        }
    }

    private func scheduleAttachment(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            if !self.attach(), attempt < 4 {
                self.scheduleAttachment(attempt: attempt + 1)
            }
        }
    }

    @discardableResult
    private func attach() -> Bool {
        guard
            let root = window?.contentView,
            let textView = root.allTextViews.first(where: {
                !$0.isEditable && $0.string == source
            }),
            let scrollView = textView.enclosingScrollView
        else {
            return false
        }

        let clipView = scrollView.contentView
        if self.clipView !== clipView {
            NotificationCenter.default.removeObserver(self)
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollPositionChanged),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(navigateToHeading),
                name: ReaderNavigation.request,
                object: nil
            )
        }

        self.textView = textView
        self.clipView = clipView
        updateActiveHeading()
        return true
    }

    @objc private func scrollPositionChanged(_ notification: Notification) {
        guard !navigationGate.isActive else { return }
        updateActiveHeading()
    }

    @objc private func navigateToHeading(_ notification: Notification) {
        guard
            notification.userInfo?["documentID"] as? String == documentID,
            let headingID = notification.userInfo?["headingID"] as? String,
            let heading = headings.first(where: { $0.id == headingID }),
            let textView,
            let clipView,
            let scrollView = textView.enclosingScrollView,
            let textLayoutManager = textView.textLayoutManager,
            let textContentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
            heading.sourceRange.location <= (textView.string as NSString).length,
            let location = textContentStorage.location(
                textContentStorage.documentRange.location,
                offsetBy: heading.sourceRange.location
            )
        else {
            return
        }

        textLayoutManager.enumerateTextLayoutFragments(
            from: location,
            options: [.ensuresLayout]
        ) { fragment in
            let proposedBounds = NSRect(
                x: clipView.bounds.origin.x,
                y: ReaderScrollGeometry.scrollOriginY(
                    fragmentMinY: fragment.layoutFragmentFrame.minY,
                    textViewMinY: textView.frame.minY,
                    textContainerOriginY: textView.textContainerOrigin.y,
                    contentInsetTop: scrollView.contentInsets.top,
                    viewportHeight: clipView.bounds.height
                ),
                width: clipView.bounds.width,
                height: clipView.bounds.height
            )
            let target = clipView.constrainBoundsRect(proposedBounds).origin
            let generation = navigationGate.begin()
            onActiveHeadingChange(heading.id)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                clipView.animator().setBoundsOrigin(target)
            }, completionHandler: { [weak self, weak clipView, weak scrollView] in
                MainActor.assumeIsolated {
                    guard
                        let self,
                        let clipView,
                        let scrollView,
                        self.navigationGate.finish(generation)
                    else {
                        return
                    }
                    clipView.scroll(to: target)
                    scrollView.reflectScrolledClipView(clipView)
                    self.updateActiveHeading()
                }
            })
            return false
        }
    }

    private func updateActiveHeading() {
        guard !headings.isEmpty else {
            onActiveHeadingChange(nil)
            return
        }
        guard
            let textView,
            let clipView,
            let textLayoutManager = textView.textLayoutManager,
            let textContentStorage = textLayoutManager.textContentManager as? NSTextContentStorage
        else {
            onActiveHeadingChange(headings.first?.id)
            return
        }

        let referenceY = ReaderScrollGeometry.textContainerY(
            scrollOriginY: clipView.bounds.minY,
            viewportHeight: clipView.bounds.height,
            textViewMinY: textView.frame.minY,
            textContainerOriginY: textView.textContainerOrigin.y
        )
        let point = CGPoint(x: 1, y: max(0, referenceY))
        guard let fragment = textLayoutManager.textLayoutFragment(for: point) else {
            onActiveHeadingChange(headings.first?.id)
            return
        }

        let offset = textContentStorage.offset(
            from: textContentStorage.documentRange.location,
            to: fragment.rangeInElement.location
        )
        let active = headings.last(where: { $0.sourceRange.location <= offset }) ?? headings.first
        onActiveHeadingChange(active?.id)
    }
}

private extension NSView {
    var allTextViews: [NSTextView] {
        var result = (self as? NSTextView).map { [$0] } ?? []
        for subview in subviews {
            result.append(contentsOf: subview.allTextViews)
        }
        return result
    }
}

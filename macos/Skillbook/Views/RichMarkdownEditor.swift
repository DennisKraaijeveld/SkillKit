import MarkdownEngine
import SwiftUI

private enum MarkdownEditorAction {
    static let bold = Notification.Name("com.denniskraaijeveld.skillkit.markdown.bold")
    static let italic = Notification.Name("com.denniskraaijeveld.skillkit.markdown.italic")
    static let heading = Notification.Name("com.denniskraaijeveld.skillkit.markdown.heading")
    static let strikethrough = Notification.Name("com.denniskraaijeveld.skillkit.markdown.strikethrough")
    static let inlineCode = Notification.Name("com.denniskraaijeveld.skillkit.markdown.inline-code")
    static let blockquote = Notification.Name("com.denniskraaijeveld.skillkit.markdown.blockquote")
    static let unorderedList = Notification.Name("com.denniskraaijeveld.skillkit.markdown.unordered-list")
    static let orderedList = Notification.Name("com.denniskraaijeveld.skillkit.markdown.ordered-list")
    static let link = Notification.Name("com.denniskraaijeveld.skillkit.markdown.link")
    static let codeBlock = Notification.Name("com.denniskraaijeveld.skillkit.markdown.code-block")
    static let horizontalRule = Notification.Name("com.denniskraaijeveld.skillkit.markdown.horizontal-rule")

    static let bus = MarkdownEditorBus(
        applyBoldRequest: bold,
        applyItalicRequest: italic,
        applyHeadingRequest: heading,
        applyStrikethroughRequest: strikethrough,
        applyInlineCodeRequest: inlineCode,
        applyBlockquoteRequest: blockquote,
        applyUnorderedListRequest: unorderedList,
        applyOrderedListRequest: orderedList,
        applyLinkRequest: link,
        applyCodeBlockRequest: codeBlock,
        applyHorizontalRuleRequest: horizontalRule
    )

    static func post(_ name: Notification.Name, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
    }
}

struct MarkdownEditorTextBuffer {
    private(set) var presentedText = ""

    mutating func synchronize(
        storedText: String,
        transform: (String) -> String
    ) {
        guard MarkdownReaderLinks.storageSource(presentedText) != storedText else { return }
        presentedText = transform(storedText)
    }

    mutating func update(_ newValue: String) -> String {
        presentedText = newValue
        return MarkdownReaderLinks.storageSource(newValue)
    }
}

struct RichMarkdownEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(ShortcutSettings.self) private var shortcuts
    @State private var showingLinkPrompt = false
    @State private var linkDestination = ""
    @State private var textBuffer = MarkdownEditorTextBuffer()

    var body: some View {
        VStack(spacing: 0) {
            formatBar
            Divider()

            NativeTextViewWrapper(
                text: editorText,
                configuration: configuration,
                fontName: "SF Pro",
                fontSize: 15,
                documentId: model.selectedId ?? "empty",
                onLinkClick: openLink,
                placeholder: NSAttributedString(
                    string: "Start writing…",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 15),
                        .foregroundColor: NSColor.placeholderTextColor,
                    ]
                ),
                header: AnyView(editorHeader),
                headerCollapsedHeight: 126,
                headerExpanded: model.yamlOpen
            )
            .frame(maxWidth: SkillbookTheme.articleMaxWidth, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SkillbookTheme.surface(.one))
        .onChange(of: model.bodyText, initial: true) { _, bodyText in
            syncPresentedText(with: bodyText)
        }
        .alert("Add link", isPresented: $showingLinkPrompt) {
            TextField("https:// or relative path", text: $linkDestination)
            Button("Cancel", role: .cancel) {
                linkDestination = ""
            }
            Button("Add") {
                MarkdownEditorAction.post(
                    MarkdownEditorAction.link,
                    userInfo: ["url": linkDestination.trimmingCharacters(in: .whitespacesAndNewlines)]
                )
                linkDestination = ""
            }
            .disabled(linkDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the destination for the selected text.")
        }
    }

    private var editorText: Binding<String> {
        return Binding(
            get: { textBuffer.presentedText },
            set: { newValue in
                model.bodyText = textBuffer.update(newValue)
            }
        )
    }

    private func syncPresentedText(with bodyText: String) {
        textBuffer.synchronize(storedText: bodyText) { storedText in
            guard let skill = model.selected else { return storedText }
            return MarkdownReaderLinks.source(
                storedText,
                documentURL: URL(fileURLWithPath: skill.skillMd),
                skillFolder: URL(fileURLWithPath: skill.folder, isDirectory: true)
            )
        }
    }

    private func openLink(_ identifier: String) {
        guard let destination = MarkdownReaderLinks.destination(from: identifier) else {
            return
        }
        model.pendingMarkdownReaderLink = destination
        model.viewMode = .read
    }

    private var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services = MarkdownEditorServices(
            wikiLinks: SkillbookMarkdownLinkResolver(),
            syntaxHighlighter: SkillbookMarkdownCodeStyle.highlighter,
            bus: MarkdownEditorAction.bus
        )
        configuration.extensions = [StrikethroughExtension()]
        configuration.textInsets = TextInsets(
            horizontal: 32,
            vertical: 18
        )
        configuration.headings = HeadingStyle(
            fontMultipliers: [1.7, 1.4, 1.2, 1.08, 1, 0.92],
            topSpacingEm: [0.32, 0.28, 0.24, 0.2, 0.16, 0.12]
        )
        configuration.paragraph = ParagraphStyle(spacingFactor: 0.28, lineHeightExtraSpacing: 2)
        configuration.overscroll = OverscrollPolicy(percent: 0.36, maxPoints: 320, minPoints: 48)
        return configuration
    }

    private var formatBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Heading 1") { applyHeading(1) }
                Button("Heading 2") { applyHeading(2) }
                Button("Heading 3") { applyHeading(3) }
            } label: {
                Label("Heading", systemImage: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            ControlGroup {
                formatButton("Bold", systemImage: "bold", action: MarkdownEditorAction.bold, shortcut: .bold)
                formatButton("Italic", systemImage: "italic", action: MarkdownEditorAction.italic, shortcut: .italic)
                formatButton("Inline code", systemImage: "chevron.left.forwardslash.chevron.right", action: MarkdownEditorAction.inlineCode)
                formatButton("Strikethrough", systemImage: "strikethrough", action: MarkdownEditorAction.strikethrough)
            }
            .controlSize(.small)

            Menu {
                Button("Bulleted list", systemImage: "list.bullet") {
                    MarkdownEditorAction.post(MarkdownEditorAction.unorderedList)
                }
                Button("Numbered list", systemImage: "list.number") {
                    MarkdownEditorAction.post(MarkdownEditorAction.orderedList)
                }
                Button("Quote", systemImage: "text.quote") {
                    MarkdownEditorAction.post(MarkdownEditorAction.blockquote)
                }
                Button("Code block", systemImage: "curlybraces") {
                    MarkdownEditorAction.post(MarkdownEditorAction.codeBlock)
                }
                Button("Link", systemImage: "link") {
                    showingLinkPrompt = true
                }
                .keyboardShortcut(shortcuts.shortcut(for: .insertLink).keyboardShortcut)
                Divider()
                Button("Divider", systemImage: "minus") {
                    MarkdownEditorAction.post(MarkdownEditorAction.horizontalRule)
                }
            } label: {
                Label("Insert", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Text("Markdown")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(SkillbookTheme.surface(.three))
    }

    private var editorHeader: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.selected?.name ?? "Untitled")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(1)

                if let description = model.selected?.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(height: 78, alignment: .topLeading)
            .padding(.top, 20)

            HStack(spacing: 12) {
                Button {
                    model.yamlOpen.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(model.yamlOpen ? 90 : 0))

                        Text("Skill settings")

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.yamlOpen ? "Expanded" : "Collapsed")

                if let skill = model.selected {
                    SkillLocationsButton(skill: skill)
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)

            if model.yamlOpen {
                SourceEditor(text: $model.yaml, syntax: .yaml)
                    .frame(height: 132)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 32)
    }

    private func formatButton(
        _ title: String,
        systemImage: String,
        action: Notification.Name,
        shortcut: AppShortcutAction? = nil
    ) -> some View {
        Button {
            MarkdownEditorAction.post(action)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .help(title)
        .modifier(EditorShortcutModifier(shortcut: shortcut, settings: shortcuts))
    }

    private func applyHeading(_ level: Int) {
        MarkdownEditorAction.post(MarkdownEditorAction.heading, userInfo: ["level": level])
    }
}

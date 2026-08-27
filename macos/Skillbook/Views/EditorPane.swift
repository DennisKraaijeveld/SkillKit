import SwiftUI

struct RawEditorPane: View {
    @Environment(AppModel.self) private var model
    @Environment(ShortcutSettings.self) private var shortcuts
    @State private var command: MarkdownEditorCommand?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        model.yamlOpen.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(model.yamlOpen ? 90 : 0))

                            Text("Frontmatter")

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

                if model.yamlOpen {
                    SourceEditor(text: $model.yaml, syntax: .yaml)
                        .frame(minHeight: 112, maxHeight: 180)
                        .frame(maxWidth: SkillbookTheme.sourceMaxWidth)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SkillbookTheme.surface(.three))

            Divider()

            markdownToolbar

            Divider()

            SourceEditor(text: $model.bodyText, syntax: .markdown, command: command)
                .frame(maxWidth: SkillbookTheme.sourceMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .background(SkillbookTheme.surface(.one))
    }

    private var markdownToolbar: some View {
        HStack(spacing: 8) {
            Text("Raw Markdown")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Menu {
                Button("Heading 1") { send(.heading(1)) }
                Button("Heading 2") { send(.heading(2)) }
                Button("Heading 3") { send(.heading(3)) }
                Divider()
                Button("Bulleted List") { send(.bulletList) }
                Button("Numbered List") { send(.numberedList) }
                Button("Quote") { send(.quote) }
                Button("Code Block") { send(.codeBlock) }
            } label: {
                Label("Block style", systemImage: "textformat.size")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Block style")

            ControlGroup {
                formatButton("Bold", systemImage: "bold", command: .bold, shortcut: .bold)
                formatButton("Italic", systemImage: "italic", command: .italic, shortcut: .italic)
                formatButton("Inline code", systemImage: "chevron.left.forwardslash.chevron.right", command: .inlineCode)
                formatButton("Link", systemImage: "link", command: .link, shortcut: .insertLink)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(SkillbookTheme.surface(.three))
    }

    private func formatButton(
        _ title: String,
        systemImage: String,
        command: MarkdownEditorCommand.Kind,
        shortcut: AppShortcutAction? = nil
    ) -> some View {
        Button { send(command) } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .help(title)
        .modifier(EditorShortcutModifier(shortcut: shortcut, settings: shortcuts))
    }

    private func send(_ kind: MarkdownEditorCommand.Kind) {
        command = MarkdownEditorCommand(kind: kind)
    }
}

struct EditorShortcutModifier: ViewModifier {
    let shortcut: AppShortcutAction?
    let settings: ShortcutSettings

    @ViewBuilder
    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(settings.shortcut(for: shortcut).keyboardShortcut)
        } else {
            content
        }
    }
}

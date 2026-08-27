import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let settingsWindowCornerRadius: CGFloat = 20

private enum SettingsPane: String, CaseIterable {
    case sources
    case updates
    case mcp
    case appearance
    case shortcuts

    var title: String {
        switch self {
        case .sources: "Sources"
        case .updates: "Updates"
        case .mcp: "MCP"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .sources: "folder"
        case .updates: "arrow.down.circle"
        case .mcp: "network"
        case .appearance: "circle.lefthalf.filled"
        case .shortcuts: "command"
        }
    }
}

private enum SettingsOperation: Equatable {
    case projectFolder
    case removeProject(String)
    case addFolder
    case removeFolder(String)
    case appearance
    case runtime(RuntimeTool)
    case refreshRuntime
}

private enum SettingsFolderPurpose: Equatable {
    case project
    case additional
}

private struct SettingsFeedback {
    var text: String
    var isError: Bool
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("settings.selectedPane") private var selectedPane = SettingsPane.sources

    var body: some View {
        SettingsContainerView(selectedPane: $selectedPane)
            .frame(width: 900, height: 640)
            .environment(model)
            .background(SkillbookTheme.surface(.one))
            .clipShape(RoundedRectangle(cornerRadius: settingsWindowCornerRadius, style: .continuous))
    }
}

private struct SettingsContainerView: View {
    @Binding var selectedPane: SettingsPane

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedPane)

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text(selectedPane.title)
                        .font(.system(size: 22, weight: .semibold))

                    Spacer()

                    SettingsCloseButton()
                }
                .padding(.leading, 28)
                .padding(.trailing, 20)
                .padding(.vertical, 18)

                SettingsPaneContent(pane: selectedPane)
            }
            .background(SkillbookTheme.surface(.one))
        }
        .background {
            SettingsWindowConfigurator()
                .frame(width: 0, height: 0)
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                SkillbookLogo(size: 42)
                Text("SkillKit")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("SkillKit")

            ForEach(SettingsPane.allCases, id: \.self) { pane in
                SettingsSidebarRow(
                    pane: pane,
                    isSelected: selection == pane,
                    onSelect: { selection = pane }
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(SkillbookTheme.surface(.two))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let currentIndex = SettingsPane.allCases.firstIndex(of: selection) else { return }

        switch direction {
        case .up:
            selection = SettingsPane.allCases[max(SettingsPane.allCases.startIndex, currentIndex - 1)]
        case .down:
            selection = SettingsPane.allCases[
                min(SettingsPane.allCases.index(before: SettingsPane.allCases.endIndex), currentIndex + 1)
            ]
        default:
            break
        }
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text(pane.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))

                Spacer()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SkillbookTheme.surface(.four))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SkillbookTheme.surface(.three))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(hovering ? SkillbookTheme.surface(.three) : .clear)
                }
                .contentShape(Circle())
        }
        .buttonStyle(SettingsCloseButtonStyle())
        .keyboardShortcut(.cancelAction)
        .onHover { hovering = $0 }
        .help("Close Settings")
        .accessibilityLabel("Close Settings")
    }
}

private struct SettingsCloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowConfigurationView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SettingsWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
    }
}

private struct SettingsPaneContent: View {
    let pane: SettingsPane

    var body: some View {
        switch pane {
        case .sources: SourcesSettingsPane()
        case .updates: UpdatesSettingsPane()
        case .mcp: MCPSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .shortcuts: ShortcutsSettingsPane()
        }
    }
}

private enum MCPSettingsOperation: Equatable {
    case install
    case configure(McpClient)
    case disconnect(McpClient)
}

private struct MCPSettingsPane: View {
    @Environment(AppModel.self) private var model
    @State private var operation: MCPSettingsOperation?
    @State private var feedback: SettingsFeedback?
    @State private var pendingDisconnect: McpClient?

    var body: some View {
        Form {
            Section {
                helperRow
            } header: {
                Text("SkillKit MCP")
            } footer: {
                Text("SkillKit installs its signed helper in Application Support. Codex, Claude Code, and Cursor start it only when they need SkillKit tools.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))

            Section {
                ForEach(McpClient.allCases) { client in
                    clientRow(client)
                }
            } header: {
                Text("Agent apps")
            } footer: {
                Text("Connect changes only the skillkit MCP entry in that app’s user configuration. Restart the agent app or begin a new session after connecting.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))

            Section {
                LabeledContent("Server executable") {
                    HStack(spacing: 8) {
                        Text(model.mcp.installedPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.mcp.installedPath)
                        Button("Copy") { copyServerPath() }
                            .disabled(!model.mcp.installed)
                    }
                }
            } header: {
                Text("Other MCP clients")
            } footer: {
                Text("Use the installed executable as a local STDIO server named skillkit in any other MCP-compatible client.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))

            if let feedback {
                Section {
                    SettingsFeedbackView(feedback: feedback)
                }
                .listRowBackground(SkillbookTheme.surface(.three))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SkillbookTheme.surface(.one))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.refreshMcpStatus() }
        .alert(
            pendingDisconnect.map { "Disconnect \($0.title)?" } ?? "Disconnect MCP?",
            isPresented: disconnectPresented,
            presenting: pendingDisconnect
        ) { client in
            Button("Disconnect", role: .destructive) { disconnect(client) }
            Button("Cancel", role: .cancel) {}
        } message: { client in
            Text("SkillKit will remove only its entry from \(client.title). The installed server and other client configurations remain unchanged.")
        }
    }

    private var helperRow: some View {
        HStack(spacing: 12) {
            Image(systemName: helperAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(helperAvailable ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(helperTitle)
                    .font(.body.weight(.medium))
                Text(helperDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if operation == .install {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.mcp.updateAvailable ? "Updating MCP server" : "Installing MCP server")
            }
            if !model.mcp.installed || model.mcp.updateAvailable {
                Button(model.mcp.updateAvailable ? "Update" : "Install") { installHelper() }
                    .disabled(operation != nil || !model.mcp.bundledAvailable)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func clientRow(_ client: McpClient) -> some View {
        let status = model.mcp[client]
        return HStack(spacing: 12) {
            Image(systemName: client.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(client.title)
                        .font(.body.weight(.medium))
                    if status?.detected == false {
                        Text("Not detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(clientDetail(status))
                    .font(.caption)
                    .foregroundStyle(clientDetailColor(status))
                    .lineLimit(2)
                    .help(status?.configPath ?? "")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if operation == .configure(client) || operation == .disconnect(client) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Updating \(client.title)")
            }

            if status?.configured == true {
                Button("Disconnect") { pendingDisconnect = client }
                    .disabled(operation != nil)
            } else {
                Button(status?.needsRepair == true ? "Repair" : "Connect") {
                    configure(client)
                }
                .disabled(operation != nil || !model.mcp.bundledAvailable || status?.conflict == true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var helperAvailable: Bool {
        model.mcp.installed && !model.mcp.updateAvailable
    }

    private var helperTitle: String {
        if !model.mcp.bundledAvailable { return "MCP helper unavailable" }
        if model.mcp.updateAvailable { return "MCP update available" }
        if model.mcp.installed { return "MCP server installed" }
        return "MCP server not installed"
    }

    private var helperDetail: String {
        if !model.mcp.bundledAvailable { return "This app build does not contain the MCP helper." }
        if model.mcp.updateAvailable { return "Update the installed helper to match this version of SkillKit." }
        if model.mcp.installed { return "Ready for configured agent apps." }
        return "Install once, then connect the agent apps you use."
    }

    private func clientDetail(_ status: McpClientStatus?) -> String {
        guard let status else { return "Status unavailable" }
        if status.configured && model.mcp.installed {
            return "Configured · Restart or start a new session"
        }
        if status.configured {
            return "Configured · MCP helper needs installation"
        }
        if let issue = status.issue { return issue }
        return status.detected ? "Available to connect" : "Connect now or after installing the app"
    }

    private func clientDetailColor(_ status: McpClientStatus?) -> Color {
        guard let status else { return .secondary }
        if status.configured && model.mcp.installed { return .green }
        if status.conflict || status.needsRepair { return .orange }
        return .secondary
    }

    private var disconnectPresented: Binding<Bool> {
        Binding(
            get: { pendingDisconnect != nil },
            set: { if !$0 { pendingDisconnect = nil } }
        )
    }

    private func installHelper() {
        guard operation == nil else { return }
        let updating = model.mcp.updateAvailable
        operation = .install
        feedback = nil
        Task {
            do {
                try await model.installMcpServer()
                feedback = SettingsFeedback(
                    text: updating ? "MCP server updated" : "MCP server installed",
                    isError: false
                )
            } catch {
                feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
            }
            operation = nil
        }
    }

    private func configure(_ client: McpClient) {
        guard operation == nil else { return }
        operation = .configure(client)
        feedback = nil
        Task {
            do {
                try await model.configureMcpClient(client)
                feedback = SettingsFeedback(
                    text: "\(client.title) configured · restart or start a new session",
                    isError: false
                )
            } catch {
                feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
            }
            operation = nil
        }
    }

    private func disconnect(_ client: McpClient) {
        guard operation == nil else { return }
        pendingDisconnect = nil
        operation = .disconnect(client)
        feedback = nil
        Task {
            do {
                try await model.disconnectMcpClient(client)
                feedback = SettingsFeedback(text: "\(client.title) disconnected", isError: false)
            } catch {
                feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
            }
            operation = nil
        }
    }

    private func copyServerPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.mcp.installedPath, forType: .string)
        feedback = SettingsFeedback(text: "Copied MCP server path", isError: false)
    }
}

private struct ShortcutFeedback: Equatable {
    var action: AppShortcutAction
    var text: String
}

private struct ShortcutsSettingsPane: View {
    @Environment(ShortcutSettings.self) private var shortcuts
    @State private var feedback: ShortcutFeedback?

    var body: some View {
        Form {
            ForEach(AppShortcutGroup.allCases) { group in
                Section(group.rawValue) {
                    ForEach(actions(in: group)) { action in
                        shortcutRow(action)
                    }
                }
                .listRowBackground(SkillbookTheme.surface(.three))
            }

            Section {
                HStack {
                    Text("Changes take effect immediately.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore All Defaults") {
                        shortcuts.restoreAllDefaults()
                        feedback = nil
                    }
                    .disabled(shortcuts.overrides.isEmpty)
                }
            } footer: {
                Text("Click a shortcut, then press a new combination. Include Command, Option, or Control; press Escape to cancel.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SkillbookTheme.surface(.one))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcutRow(_ action: AppShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(action.title)
                Spacer(minLength: 12)
                ShortcutRecorder(
                    title: action.title,
                    shortcut: shortcuts.shortcut(for: action),
                    onRecord: { assign($0, to: action) },
                    onInvalid: { feedback = ShortcutFeedback(action: action, text: $0) }
                )
                .frame(width: 116, height: 26)

                Button {
                    if let issue = shortcuts.restoreDefault(for: action) {
                        feedback = ShortcutFeedback(action: action, text: issue.message)
                    } else if feedback?.action == action {
                        feedback = nil
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!shortcuts.isCustomized(action))
                .help("Restore default shortcut")
                .accessibilityLabel("Restore default shortcut for \(action.title)")
            }

            if feedback?.action == action, let text = feedback?.text {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func actions(in group: AppShortcutGroup) -> [AppShortcutAction] {
        AppShortcutAction.allCases.filter { $0.group == group }
    }

    private func assign(_ shortcut: AppShortcut, to action: AppShortcutAction) {
        if let issue = shortcuts.assign(shortcut, to: action) {
            feedback = ShortcutFeedback(action: action, text: issue.message)
        } else {
            feedback = nil
        }
    }
}

private struct SourcesSettingsPane: View {
    @Environment(AppModel.self) private var model
    @State private var pickingFolder = false
    @State private var folderPurpose = SettingsFolderPurpose.project
    @State private var operation: SettingsOperation?
    @State private var feedback: SettingsFeedback?
    @State private var pickingExecutable = false
    @State private var executableTool = RuntimeTool.npx

    var body: some View {
        Form {
            Section {
                if model.config.projectRoots.isEmpty {
                    Text("No work folders")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.config.projectRoots, id: \.self) { path in
                        projectFolderRow(path: path)
                    }
                }

                Button("Add Work Folder…") { chooseFolder(for: .project) }
                    .disabled(operation != nil)
            } header: {
                Text("Work folders")
            } footer: {
                Text("Finds project-specific skills and overrides inside supported agent folders. Worktrees and project copies already covered globally stay hidden.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))

            Section {
                if model.config.customRoots.isEmpty {
                    Text("No additional folders")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.config.customRoots, id: \.self) { path in
                        folderRow(path: path)
                    }
                }

                Button("Add Folder…") { chooseFolder(for: .additional) }
                    .disabled(operation != nil)
            } header: {
                Text("Additional folders")
            } footer: {
                Text("Scan folders outside the project and detected agent locations.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))

            Section {
                ForEach(RuntimeTool.allCases) { tool in
                    runtimeToolRow(tool)
                }

                HStack {
                    Text("SkillKit checks these tools without running your shell profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check again") { refreshRuntime() }
                        .disabled(operation != nil)
                }
            } header: {
                Text("Command-line tools")
            } footer: {
                Text("Automatic discovery supports standard paths and common Node managers. Choose an executable only when automatic detection cannot find it.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))

            Section {
                ForEach(detectedFolders) { directory in
                    detectedFolderRow(directory)
                }
            } header: {
                HStack {
                    Text("Detected agent folders")
                    Spacer()
                    Text("\(availableFolderCount) of \(model.config.globalDirs.count) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            } footer: {
                Text("SkillKit checks common agent folders automatically.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))

            if let feedback {
                Section {
                    SettingsFeedbackView(feedback: feedback)
                }
                .listRowBackground(SkillbookTheme.surface(.three))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SkillbookTheme.surface(.one))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            handlePickedFolder(result, asProjectFolder: folderPurpose == .project)
        }
        .fileImporter(isPresented: $pickingExecutable, allowedContentTypes: [.unixExecutable]) { result in
            handlePickedExecutable(result, tool: executableTool)
        }
    }

    private func runtimeToolRow(_ tool: RuntimeTool) -> some View {
        let status = model.runtime[tool]
        let override = configuredPath(for: tool)
        return HStack(spacing: 12) {
            Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status.isAvailable ? .green : .red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.rawValue)
                        .font(.body.weight(.medium))
                    if let version = status.version, status.isAvailable {
                        Text(version)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(status.state == .invalid ? "Invalid selection" : "Not found")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text(status.path ?? status.issue ?? "Automatic")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(status.path ?? status.issue ?? "Automatic discovery")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if operation == .runtime(tool) {
                ProgressView()
                    .controlSize(.small)
            }
            if override != nil {
                Button("Automatic") { setRuntimeTool(tool, path: nil) }
                    .disabled(operation != nil)
            }
            Button("Choose…") {
                executableTool = tool
                pickingExecutable = true
            }
            .disabled(operation != nil)
        }
        .accessibilityElement(children: .contain)
    }

    private func chooseFolder(for purpose: SettingsFolderPurpose) {
        folderPurpose = purpose
        pickingFolder = true
    }

    private func configuredPath(for tool: RuntimeTool) -> String? {
        switch tool {
        case .git: model.config.gitPath
        case .npx: model.config.npxPath
        }
    }

    private func refreshRuntime() {
        guard operation == nil else { return }
        operation = .refreshRuntime
        feedback = nil
        Task {
            let status = await model.refreshRuntime()
            let available = [status.git, status.npx].count(where: \.isAvailable)
            feedback = SettingsFeedback(text: "Checked tools · \(available) of 2 available", isError: false)
            operation = nil
        }
    }

    private func setRuntimeTool(_ tool: RuntimeTool, path: String?) {
        guard operation == nil else { return }
        operation = .runtime(tool)
        feedback = nil
        Task {
            do {
                let status = try await model.setRuntimeTool(tool, path: path)
                let toolStatus = status[tool]
                feedback = SettingsFeedback(
                    text: toolStatus.isAvailable
                        ? "\(tool.rawValue) \(toolStatus.version ?? "available")"
                        : (toolStatus.issue ?? "\(tool.rawValue) was not found"),
                    isError: !toolStatus.isAvailable
                )
            } catch {
                feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
            }
            operation = nil
        }
    }

    private func handlePickedExecutable(_ result: Result<URL, Error>, tool: RuntimeTool) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            setRuntimeTool(tool, path: url.path)
            if scoped { url.stopAccessingSecurityScopedResource() }
        case .failure(let error):
            let failure = error as NSError
            guard failure.code != NSUserCancelledError else { return }
            feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
        }
    }

    private func projectFolderRow(path: String) -> some View {
        HStack(spacing: 12) {
            FolderIdentity(path: path)
            Spacer(minLength: 12)
            if operation == .removeProject(path) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Removing \(folderName(path))")
            }
            Button("Open in Finder") { model.revealPath(path) }
                .accessibilityLabel("Open \(folderName(path)) in Finder")
            Button("Remove") { removeProjectFolder(path) }
                .disabled(operation != nil)
                .accessibilityLabel("Remove \(folderName(path)) from SkillKit")
        }
    }

    private func folderRow(path: String) -> some View {
        HStack(spacing: 12) {
            FolderIdentity(path: path)
            Spacer(minLength: 12)
            if operation == .removeFolder(path) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Removing \(folderName(path))")
            }
            Button("Open in Finder") { model.revealPath(path) }
                .accessibilityLabel("Open \(folderName(path)) in Finder")
            Button("Copy") { copyPath(path) }
                .accessibilityLabel("Copy path for \(folderName(path))")
            Button("Remove") { removeAdditionalFolder(path) }
                .disabled(operation != nil)
                .accessibilityLabel("Remove \(folderName(path)) from SkillKit")
        }
    }

    private func detectedFolderRow(_ directory: GlobalDir) -> some View {
        let name = agentName(directory.agent)
        return HStack(spacing: 10) {
            ToolMark(name: directory.agent, size: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                Text(directory.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(directory.path)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: directory.exists ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(directory.exists ? Color.green : Color.secondary)
                Text(directory.exists ? "Available" : "Not found")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .frame(width: 78, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name) skill folder")
            .accessibilityValue(directory.exists ? "Available" : "Not found")

            if directory.exists {
                Button {
                    model.revealPath(directory.path)
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Open \(name) skill folder in Finder")
                .accessibilityLabel("Open \(name) skill folder in Finder")
            } else {
                Color.clear
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
        }
    }

    private var detectedFolders: [GlobalDir] {
        model.config.globalDirs.sorted {
            if $0.exists != $1.exists { return $0.exists && !$1.exists }
            return agentName($0.agent).localizedStandardCompare(agentName($1.agent)) == .orderedAscending
        }
    }

    private var availableFolderCount: Int {
        model.config.globalDirs.count(where: \.exists)
    }

    private func removeProjectFolder(_ path: String) {
        guard operation == nil else { return }
        operation = .removeProject(path)
        feedback = nil
        Task {
            do {
                let status = try await model.removeProjectRoot(path)
                feedback = SettingsFeedback(text: "Removed project · \(status)", isError: false)
            } catch {
                feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
            }
            operation = nil
        }
    }

    private func removeAdditionalFolder(_ path: String) {
        guard operation == nil else { return }
        operation = .removeFolder(path)
        feedback = nil
        Task {
            do {
                let status = try await model.removeCustomRoot(path)
                feedback = SettingsFeedback(text: "Removed folder · \(status)", isError: false)
            } catch {
                feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
            }
            operation = nil
        }
    }

    private func handlePickedFolder(_ result: Result<URL, Error>, asProjectFolder: Bool) {
        switch result {
        case .success(let url):
            savePickedFolder(url, asProjectFolder: asProjectFolder)
        case .failure(let error):
            let failure = error as NSError
            guard failure.code != NSUserCancelledError else { return }
            feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
        }
    }

    private func savePickedFolder(_ url: URL, asProjectFolder: Bool) {
        guard operation == nil else { return }
        operation = asProjectFolder ? .projectFolder : .addFolder
        feedback = nil
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let status = if asProjectFolder {
                    try await model.addProjectRoot(url.path)
                } else {
                    try await model.addCustomRoot(url.path)
                }
                feedback = SettingsFeedback(
                    text: asProjectFolder
                        ? "Added work folder · \(status)"
                        : "Added folder · \(status)",
                    isError: false
                )
            } catch {
                feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
            }
            operation = nil
        }
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        feedback = SettingsFeedback(text: "Copied path", isError: false)
    }

    private func folderName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func agentName(_ agent: String) -> String {
        SkillHost(agent: agent)?.title ?? agent.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private struct AppearanceSettingsPane: View {
    @Environment(AppModel.self) private var model
    @State private var operation: SettingsOperation?
    @State private var feedback: SettingsFeedback?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("Appearance") {
                    HStack {
                        AdaptiveSegmentedPicker(
                            "Appearance",
                            selection: $model.appearance,
                            values: ["system", "light", "dark"],
                            showsLabel: false,
                            optionTitle: { $0.capitalized }
                        )
                        .frame(width: 300)
                        .disabled(operation != nil)
                        .onChange(of: model.appearance) { _, mode in
                            saveAppearance(mode)
                        }

                        if operation == .appearance {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving appearance")
                        }
                    }
                }
            } footer: {
                Text("System follows macOS while using SkillKit’s light and dark surface palette.")
            }
            .listRowBackground(SkillbookTheme.surface(.three))

            if let feedback {
                Section {
                    SettingsFeedbackView(feedback: feedback)
                }
                .listRowBackground(SkillbookTheme.surface(.three))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SkillbookTheme.surface(.one))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func saveAppearance(_ mode: String) {
        guard operation == nil, mode != model.config.appearance else { return }
        operation = .appearance
        feedback = nil
        Task {
            do {
                try await model.saveAppearance(mode)
                feedback = SettingsFeedback(text: "Appearance saved", isError: false)
            } catch {
                feedback = SettingsFeedback(text: error.localizedDescription, isError: true)
            }
            operation = nil
        }
    }
}

private struct FolderIdentity: View {
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(URL(fileURLWithPath: path).lastPathComponent)
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsFeedbackView: View {
    let feedback: SettingsFeedback

    var body: some View {
        Label(
            feedback.text,
            systemImage: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle"
        )
        .font(.caption)
        .foregroundStyle(feedback.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        .textSelection(.enabled)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

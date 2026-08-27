import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(ApplicationUpdater.self) private var applicationUpdater
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            DetailView()
        }
        .navigationTitle(model.windowTitle)
        .navigationSubtitle(model.selected?.path ?? "")
        .toolbar { toolbarContent }
        .background(SkillbookTheme.surface(.two))
        .background {
            WindowChrome(dirty: model.dirty, title: model.windowTitle)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Self.importDroppedFolders(providers) { path in
                Task {
                    do {
                        try await model.addCustomRoot(path)
                        model.flash("Added folder")
                    } catch {
                        model.error = error.localizedDescription
                    }
                }
            }
        }
        .overlay { dropHighlight }
        .modifier(WorkspacePresentations())
        .safeAreaInset(edge: .bottom, spacing: 0) { errorBanner }
        .overlay(alignment: .bottomTrailing) { floatingNotices }
        .task { await model.startWatching() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if applicationUpdater.phase.showsToolbarItem {
            ToolbarItem {
                AppUpdateToolbarControl()
            }
        }
        ToolbarItemGroup {
            Menu {
                if model.selected != nil {
                    Button {
                        model.presentUseInProject()
                    } label: {
                        Label("Use in Project…", systemImage: "folder.badge.plus")
                    }
                    Divider()
                }
                Button {
                    model.showInstallSheet = true
                } label: {
                    Label("Install Skill…", systemImage: "square.and.arrow.down")
                }
                Button {
                    model.showNewSkillSheet = true
                } label: {
                    Label("New SKILL.md…", systemImage: "doc.badge.plus")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("Add")
                }
            }
            .help("Add a skill")
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if dropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var floatingNotices: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let toast = model.toast {
                Text(toast)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .skillbookSurface(.five, in: Capsule())
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !model.progress.isIdle {
                JobProgressToast(progress: model.progress, onCancel: model.cancelJob)
            }
        }
        .padding(16)
        .animation(.easeOut(duration: 0.2), value: model.progress.isIdle)
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.error {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss") { model.error = nil }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SkillbookTheme.surface(.three))
            .overlay(alignment: .top) { Divider() }
        }
    }

    private static func importDroppedFolders(
        _ providers: [NSItemProvider],
        into apply: @escaping @MainActor @Sendable (String) -> Void
    ) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = {
                    if let url = item as? URL { return url }
                    if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                    if let text = item as? String { return URL(fileURLWithPath: text) }
                    return nil
                }()
                guard let url else { return }
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                guard isDir.boolValue else { return }
                Task { @MainActor in
                    apply(url.path)
                }
            }
        }
        return accepted
    }
}

private struct WorkspacePresentations: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(isPresented: $model.showUpdateSheet) {
                UpdateSheet()
            }
            .sheet(isPresented: $model.showInstallSheet) {
                InstallSheet()
            }
            .sheet(isPresented: $model.showNewSkillSheet) {
                NewSkillSheet()
            }
            .sheet(
                isPresented: $model.showProjectUseSheet,
                onDismiss: { model.projectUseSkillId = nil }
            ) {
                ProjectUseSheet()
            }
            .sheet(isPresented: $model.showDuplicateSheet) {
                DuplicateSheet()
            }
            .confirmationDialog(
                model.confirmTitle,
                isPresented: $model.confirmDiscard,
                titleVisibility: .visible
            ) {
                if model.confirmShowsSave {
                    Button("Save") { model.saveThenPending() }
                }
                Button(model.confirmActionLabel, role: .destructive) {
                    model.confirmPending()
                }
                Button("Cancel", role: .cancel) {
                    model.cancelPending()
                }
            } message: {
                Text(model.confirmMessage)
            }
            .alert("Move to Trash?", isPresented: $model.confirmDelete) {
                Button("Move to Trash", role: .destructive) { model.deletePending() }
                Button("Cancel", role: .cancel) { model.cancelDelete() }
            } message: {
                Text("“\(model.deleteConfirmName)” and its folder will be moved to the Trash.")
            }
            .fileImporter(isPresented: $model.pickingScanRoot, allowedContentTypes: [.folder]) { result in
                handleScanRoot(result)
            }
    }

    private func handleScanRoot(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let status = try await model.addProjectRoot(url.path)
                    model.flash("Added work folder · \(status)")
                } catch {
                    model.error = error.localizedDescription
                }
            }
        case .failure(let error):
            let failure = error as NSError
            guard failure.code != NSUserCancelledError else { return }
            model.error = error.localizedDescription
        }
    }
}

struct JobProgressToast: View {
    let progress: JobProgress
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 12)
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
            }
            if progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(minWidth: 220, maxWidth: 280, alignment: .leading)
        .skillbookSurface(.six, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var title: String {
        switch progress.phase {
        case "check": "Checking skills"
        case "update": "Updating"
        case "install": progress.name.isEmpty ? "Installing" : "Installing \(progress.name)"
        default: "Working"
        }
    }

    private var detail: String {
        if progress.total > 0 {
            let counts = "\(progress.done) of \(progress.total)"
            return progress.name.isEmpty ? counts : "\(counts) · \(progress.name)"
        }
        return progress.label.isEmpty ? "In progress" : progress.label
    }
}

struct WindowChrome: NSViewRepresentable {
    var dirty: Bool
    var title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else {
            DispatchQueue.main.async {
                guard let window = view.window else { return }
                if window.isDocumentEdited != dirty { window.isDocumentEdited = dirty }
                if window.title != title { window.title = title }
            }
            return
        }
        if window.isDocumentEdited != dirty { window.isDocumentEdited = dirty }
        if window.title != title { window.title = title }
    }
}

#Preview {
    WorkspaceView()
        .environment(AppModel(backend: PreviewBackend()))
        .environment(ShortcutSettings())
        .environment(ApplicationUpdater())
        .frame(width: 1100, height: 720)
}

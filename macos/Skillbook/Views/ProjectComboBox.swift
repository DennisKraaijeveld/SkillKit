import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectComboBoxNavigation {
    private(set) var keyboardPath: String?
    private(set) var hoveredPath: String?
    private(set) var scrollPath: String?

    mutating func reset(to path: String?) {
        keyboardPath = path
        hoveredPath = nil
        scrollPath = path
    }

    mutating func hover(_ path: String, isInside: Bool) {
        if isInside {
            hoveredPath = path
        } else if hoveredPath == path {
            hoveredPath = nil
        }
    }

    mutating func move(
        _ direction: MoveCommandDirection,
        through paths: [String]
    ) -> String? {
        guard !paths.isEmpty else { return nil }
        hoveredPath = nil
        let current = keyboardPath.flatMap(paths.firstIndex(of:))
        switch direction {
        case .down:
            keyboardPath = paths[min((current ?? -1) + 1, paths.count - 1)]
        case .up:
            keyboardPath = paths[max((current ?? paths.count) - 1, 0)]
        default:
            return nil
        }
        scrollPath = keyboardPath
        return scrollPath
    }
}

struct ProjectComboBox: View {
    @Binding var selection: String
    let projects: [ProjectCandidate]
    let recentPaths: [String]
    var disabled = false
    var onFolderError: (String) -> Void = { _ in }

    @State private var presented = false
    @State private var pickingFolder = false

    var body: some View {
        Button {
            presented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedName)
                        .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    if !selection.isEmpty {
                        Text(abbreviatedSelection)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(SkillbookTheme.surface(.three), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        }
        .disabled(disabled)
        .accessibilityLabel("Project")
        .accessibilityValue(selection.isEmpty ? "No project selected" : "\(selectedName), \(selection)")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            ProjectComboBoxPopover(
                selection: $selection,
                presented: $presented,
                projects: projects,
                recentPaths: recentPaths,
                addFolder: {
                    presented = false
                    pickingFolder = true
                }
            )
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                selection = url.standardizedFileURL.path
            case .failure(let error):
                let failure = error as NSError
                guard failure.code != NSUserCancelledError else { return }
                onFolderError(error.localizedDescription)
            }
        }
    }

    private var selectedProject: ProjectCandidate? {
        projects.first { $0.path == selection }
    }

    private var selectedName: String {
        if selection.isEmpty { return "Choose a project" }
        return selectedProject?.name ?? URL(fileURLWithPath: selection).lastPathComponent
    }

    private var abbreviatedSelection: String {
        selectedProject?.abbreviatedPath ?? (selection as NSString).abbreviatingWithTildeInPath
    }
}

private struct ProjectComboBoxPopover: View {
    @Binding var selection: String
    @Binding var presented: Bool
    let projects: [ProjectCandidate]
    let recentPaths: [String]
    let addFolder: () -> Void

    @State private var query = ""
    @State private var navigation = ProjectComboBoxNavigation()
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Project name or path", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit(selectHighlighted)
                        .accessibilityLabel("Search projects")
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)

                Divider()

                if results.isEmpty {
                    ContentUnavailableView(
                        "No projects found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another name or add a project folder.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    List {
                        ForEach(results) { project in
                            projectButton(project)
                                .id(project.path)
                                .listRowInsets(
                                    EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6)
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: resultListHeight)
                }

                Divider()

                Button(action: addFolder) {
                    Label("Add Project Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Finder to choose a project outside the listed work folders")
            }
            .frame(width: 390)
            .background(SkillbookTheme.surface(.two))
            .onAppear {
                let initialPath = results.contains(where: { $0.path == selection })
                    ? selection
                    : results.first?.path
                navigation.reset(to: initialPath)
                Task { @MainActor in searchFocused = true }
            }
            .onChange(of: query) { _, _ in
                let path = results.first?.path
                navigation.reset(to: path)
                guard let path else { return }
                Task { @MainActor in proxy.scrollTo(path, anchor: .top) }
            }
            .onMoveCommand { direction in
                guard let path = navigation.move(
                    direction,
                    through: results.map(\.path)
                ) else { return }
                proxy.scrollTo(path)
            }
            .onExitCommand { presented = false }
        }
    }

    private var results: [ProjectCandidate] {
        ProjectSearch.results(projects, query: query, recentPaths: recentPaths)
    }

    private var resultListHeight: CGFloat {
        min(260, max(150, CGFloat(results.count) * 44 + 4))
    }

    private func projectButton(_ project: ProjectCandidate) -> some View {
        Button {
            select(project)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == project.path ? "folder.fill" : "folder")
                    .foregroundStyle(selection == project.path ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .lineLimit(1)
                    Text(project.abbreviatedPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selection == project.path {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Selected")
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
            .background(
                rowBackground(for: project),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            navigation.hover(project.path, isInside: hovering)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(project.path)")
        .accessibilityValue(selection == project.path ? "Selected" : "")
    }

    private func rowBackground(for project: ProjectCandidate) -> AnyShapeStyle {
        if navigation.keyboardPath == project.path {
            return AnyShapeStyle(.selection)
        }
        if navigation.hoveredPath == project.path {
            return AnyShapeStyle(.fill.quaternary)
        }
        return AnyShapeStyle(.clear)
    }

    private func selectHighlighted() {
        guard let highlightedPath = navigation.keyboardPath,
              let project = results.first(where: { $0.path == highlightedPath })
        else { return }
        select(project)
    }

    private func select(_ project: ProjectCandidate) {
        selection = project.path
        presented = false
    }
}

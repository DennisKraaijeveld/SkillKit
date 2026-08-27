import SwiftUI

struct DuplicateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Duplicate checker")
                        .font(.headline)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            if model.duplicateGroups.isEmpty {
                ContentUnavailableView(
                    "No independent duplicates",
                    systemImage: "checkmark.circle",
                    description: Text("Symlinked placements already count as one shared skill.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.duplicateGroups) { group in
                        Section {
                            ForEach(group.skills) { skill in
                                duplicateRow(skill)
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                Text("\(group.skills.count) independent copies · \(group.reason)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 640, height: 500)
        .background(SkillbookTheme.surface(.two))
    }

    private var summary: String {
        let count = model.duplicateCopyCount
        if count == 0 { return "Independent copies are checked by source and content." }
        return count == 1
            ? "1 extra copy needs review. No files will be changed."
            : "\(count) extra copies need review. No files will be changed."
    }

    private func duplicateRow(_ skill: SkillRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: scopeSymbol(skill.scope))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(locationTitle(skill))
                        .font(.body.weight(.medium))
                    Text(skill.scope.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(skill.folder)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(skill.folder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open in Finder") { model.revealInFinder(skill) }
                .controlSize(.small)
            Button("Copy Path") { model.copyPath(skill) }
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func locationTitle(_ skill: SkillRow) -> String {
        if let root = skill.placements.compactMap(\.root).first {
            return URL(fileURLWithPath: root).lastPathComponent
        }
        return URL(fileURLWithPath: skill.folder).deletingLastPathComponent().lastPathComponent
    }

    private func scopeSymbol(_ scope: SkillScope) -> String {
        switch scope {
        case .global: "globe"
        case .project: "folder"
        case .custom: "externaldrive"
        }
    }
}

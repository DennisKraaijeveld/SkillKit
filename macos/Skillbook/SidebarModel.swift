import Foundation

struct SidebarSkillItem: Identifiable, Hashable {
    var id: String
    var skill: SkillRow
    var additionalCopies: [SkillRow]
    var agents: [String]
    var isLinked: Bool

    var copyCount: Int { additionalCopies.count + 1 }

    var latestModifiedAt: Date? {
        var latest = skill.modifiedAt
        for copy in additionalCopies {
            guard let modifiedAt = copy.modifiedAt else { continue }
            latest = max(latest ?? modifiedAt, modifiedAt)
        }
        return latest
    }

    func copy(skillId: String?) -> SkillRow? {
        guard let skillId else { return nil }
        if skill.id == skillId { return skill }
        return additionalCopies.first { $0.id == skillId }
    }

    func contains(skillId: String?) -> Bool {
        copy(skillId: skillId) != nil
    }
}

struct SidebarCategoryGroup: Identifiable, Hashable {
    var id: String
    var title: String
    var skills: [SidebarSkillItem]
}

struct SidebarCollectionGroup: Identifiable, Hashable {
    var id: String
    var title: String
    var kind: String
    var skills: [SidebarSkillItem]
    var categories: [SidebarCategoryGroup]

    var allSkills: [SidebarSkillItem] {
        skills + categories.flatMap(\.skills)
    }

    var skillCount: Int {
        allSkills.count
    }

    var updateCount: Int {
        allSkills.reduce(0) {
            $0 + ($1.skill.version == .updateAvailable ? 1 : 0)
        }
    }

    var containsLinkedSkill: Bool {
        allSkills.contains(where: \.isLinked)
    }
}

struct SidebarLocationGroup: Identifiable, Hashable {
    var id: String
    var title: String
    var path: String?
    var scope: SkillScope
    var skills: [SidebarSkillItem]
    var collections: [SidebarCollectionGroup]

    var skillCount: Int {
        skills.count + collections.reduce(0) { $0 + $1.skillCount }
    }

    var allSkills: [SidebarSkillItem] {
        skills + collections.flatMap(\.allSkills)
    }
}

struct SidebarSectionGroup: Identifiable, Hashable {
    var scope: SkillScope
    var locations: [SidebarLocationGroup]

    var id: String { scope.rawValue }
    var title: String { scope.rawValue }
    var skillCount: Int { locations.reduce(0) { $0 + $1.skillCount } }
}

enum SidebarTree {
    static func build(skills: [SkillRow]) -> [SidebarSectionGroup] {
        var locations: [LocationKey: [SidebarSkillItem]] = [:]

        for skill in skills {
            let availablePlacements = skill.placements.isEmpty
                ? [fallbackPlacement(for: skill)]
                : skill.placements
            let globalPlacements = availablePlacements.filter { $0.scope == .global }
            let placements = skill.scope == .global && !globalPlacements.isEmpty
                ? globalPlacements
                : availablePlacements
            let grouped = Dictionary(grouping: placements, by: LocationKey.init)
            for (location, links) in grouped {
                let agents = Array(Set(links.map(\.agent))).sorted()
                let item = SidebarSkillItem(
                    id: "\(location.id)::\(skill.id)",
                    skill: skill,
                    additionalCopies: [],
                    agents: agents,
                    isLinked: links.allSatisfy(\.isSymlink)
                )
                locations[location, default: []].append(item)
            }
        }

        return SkillScope.allCases.compactMap { scope in
            let scopedLocations = locations
                .filter { $0.key.scope == scope }
                .map { key, items in
                    let collapsed = collapseExactCopies(items, locationId: key.id)
                    return SidebarLocationGroup(
                        id: key.id,
                        title: key.title,
                        path: key.path,
                        scope: scope,
                        skills: scope == .global ? [] : collapsed.sorted(by: skillOrder),
                        collections: scope == .global
                            ? collections(for: collapsed, locationId: key.id)
                            : []
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.scope == .global { return lhs.id < rhs.id }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            guard !scopedLocations.isEmpty else { return nil }
            return SidebarSectionGroup(scope: scope, locations: scopedLocations)
        }
    }

    static func item(id: String, in sections: [SidebarSectionGroup]) -> SidebarSkillItem? {
        for section in sections {
            for location in section.locations {
                if let item = location.skills.first(where: { $0.id == id }) {
                    return item
                }
                for collection in location.collections {
                    if let item = collection.skills.first(where: { $0.id == id }) {
                        return item
                    }
                    for category in collection.categories {
                        if let item = category.skills.first(where: { $0.id == id }) {
                            return item
                        }
                    }
                }
            }
        }
        return nil
    }

    static func firstItem(for skillId: String, in sections: [SidebarSectionGroup]) -> SidebarSkillItem? {
        for section in sections {
            for location in section.locations {
                if let item = location.skills.first(where: { $0.contains(skillId: skillId) }) {
                    return item
                }
                for collection in location.collections {
                    if let item = collection.skills.first(where: { $0.contains(skillId: skillId) }) {
                        return item
                    }
                    for category in collection.categories {
                        if let item = category.skills.first(where: { $0.contains(skillId: skillId) }) {
                            return item
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func collapseExactCopies(
        _ items: [SidebarSkillItem],
        locationId: String
    ) -> [SidebarSkillItem] {
        var collapsed: [SidebarSkillItem] = []
        collapsed.reserveCapacity(items.count)
        var indexByExactKey: [String: Int] = [:]
        indexByExactKey.reserveCapacity(items.count)

        for item in items {
            let exactKey = item.skill.exactDuplicateKey.isEmpty
                ? "skill:\(item.skill.id)"
                : item.skill.exactDuplicateKey
            guard let index = indexByExactKey[exactKey] else {
                indexByExactKey[exactKey] = collapsed.count
                collapsed.append(item)
                continue
            }

            var existing = collapsed[index]
            if preferredCopyOrder(item, existing) {
                existing.additionalCopies.append(existing.skill)
                existing.skill = item.skill
            } else {
                existing.additionalCopies.append(item.skill)
            }
            existing.id = "\(locationId)::exact::\(exactKey)"
            existing.additionalCopies.append(contentsOf: item.additionalCopies)
            existing.agents = Array(Set(existing.agents).union(item.agents)).sorted()
            existing.isLinked = existing.isLinked && item.isLinked
            collapsed[index] = existing
        }

        return collapsed
    }

    private static func collections(
        for items: [SidebarSkillItem],
        locationId: String
    ) -> [SidebarCollectionGroup] {
        Dictionary(grouping: items, by: { $0.skill.collectionId })
            .map { collectionId, collectionItems in
                let sorted = collectionItems.sorted(by: skillOrder)
                let categoryNames = Set(sorted.compactMap { $0.skill.sourceCategory })
                let showCategories = sorted.count >= 6 && categoryNames.count >= 2
                let direct = showCategories
                    ? sorted.filter { $0.skill.sourceCategory == nil }
                    : sorted
                let categories = showCategories
                    ? Dictionary(
                        grouping: sorted.filter { $0.skill.sourceCategory != nil },
                        by: { $0.skill.sourceCategory ?? "" }
                    )
                    .map { category, categoryItems in
                        SidebarCategoryGroup(
                            id: "\(locationId)::\(collectionId)::category::\(category)",
                            title: displayName(category),
                            skills: categoryItems.sorted(by: skillOrder)
                        )
                    }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    : []
                return SidebarCollectionGroup(
                    id: "\(locationId)::collection::\(collectionId)",
                    title: sorted[0].skill.collectionLabel,
                    kind: sorted[0].skill.sourceKind,
                    skills: direct,
                    categories: categories
                )
            }
            .sorted { lhs, rhs in
                if lhs.kind == "local", rhs.kind != "local" { return false }
                if lhs.kind != "local", rhs.kind == "local" { return true }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private static func fallbackPlacement(for skill: SkillRow) -> SkillPlacement {
        SkillPlacement(
            agent: skill.agents.first ?? "local",
            path: skill.folder,
            scope: skill.scope,
            root: skill.scope == .global ? nil : skill.folder,
            isSymlink: false
        )
    }

    private static func skillOrder(_ lhs: SidebarSkillItem, _ rhs: SidebarSkillItem) -> Bool {
        let names = lhs.skill.name.localizedCaseInsensitiveCompare(rhs.skill.name)
        return names == .orderedSame
            ? lhs.skill.folder < rhs.skill.folder
            : names == .orderedAscending
    }

    private static func preferredCopyOrder(_ lhs: SidebarSkillItem, _ rhs: SidebarSkillItem) -> Bool {
        let lhsRank = copyRank(lhs)
        let rhsRank = copyRank(rhs)
        return lhsRank == rhsRank
            ? lhs.skill.folder < rhs.skill.folder
            : lhsRank < rhsRank
    }

    private static func copyRank(_ item: SidebarSkillItem) -> Int {
        if !item.isLinked, item.agents.contains("agents") { return 0 }
        return item.isLinked ? 2 : 1
    }

    private static func displayName(_ value: String) -> String {
        value
            .split(separator: "/")
            .map { segment in
                segment
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: "-")
                    .map { $0.capitalized }
                    .joined(separator: " ")
            }
            .joined(separator: " / ")
    }

    private struct LocationKey: Hashable {
        var scope: SkillScope
        var path: String?

        init(_ placement: SkillPlacement) {
            scope = placement.scope
            path = placement.scope == .global ? nil : placement.root ?? placement.path
        }

        var id: String {
            switch scope {
            case .global: "global"
            case .project: "project:\(path ?? "unknown")"
            case .custom: "custom:\(path ?? "unknown")"
            }
        }

        var title: String {
            guard let path else { return "Global" }
            let name = URL(fileURLWithPath: path).lastPathComponent
            return name.isEmpty ? path : name
        }
    }
}

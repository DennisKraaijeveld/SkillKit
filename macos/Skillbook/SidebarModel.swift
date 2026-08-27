import Foundation

struct SidebarSkillItem: Identifiable, Hashable {
    var id: String
    var skill: SkillRow
    var agents: [String]
    var isLinked: Bool
    var placementPath: String
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
                    agents: agents,
                    isLinked: links.allSatisfy(\.isSymlink),
                    placementPath: links.sorted { $0.path < $1.path }[0].path
                )
                locations[location, default: []].append(item)
            }
        }

        return SkillScope.allCases.compactMap { scope in
            let scopedLocations = locations
                .filter { $0.key.scope == scope }
                .map { key, items in
                    SidebarLocationGroup(
                        id: key.id,
                        title: key.title,
                        path: key.path,
                        scope: scope,
                        skills: scope == .global ? [] : items.sorted(by: skillOrder),
                        collections: scope == .global
                            ? collections(for: items, locationId: key.id)
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
                if let item = location.skills.first(where: { $0.skill.id == skillId }) {
                    return item
                }
                for collection in location.collections {
                    if let item = collection.skills.first(where: { $0.skill.id == skillId }) {
                        return item
                    }
                    for category in collection.categories {
                        if let item = category.skills.first(where: { $0.skill.id == skillId }) {
                            return item
                        }
                    }
                }
            }
        }
        return nil
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
        lhs.skill.name.localizedCaseInsensitiveCompare(rhs.skill.name) == .orderedAscending
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

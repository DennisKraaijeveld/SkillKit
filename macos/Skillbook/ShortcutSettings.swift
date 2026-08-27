import AppKit
import Foundation
import Observation
import SwiftUI

enum AppShortcutGroup: String, CaseIterable, Identifiable {
    case navigation = "Navigation"
    case library = "Library"
    case editor = "Editor"
    case selectedSkill = "Selected skill"

    var id: String { rawValue }
}

enum AppShortcutAction: String, CaseIterable, Codable, Identifiable {
    case searchSkills
    case editView
    case readView
    case rawView
    case newSkill
    case installSkill
    case save
    case reloadSkills
    case checkForUpdates
    case bold
    case italic
    case insertLink
    case openInDefaultApp
    case revealInFinder
    case showLocations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .searchSkills: "Search Skills"
        case .editView: "Edit"
        case .readView: "Read"
        case .rawView: "Raw"
        case .newSkill: "New Skill"
        case .installSkill: "Install Skill"
        case .save: "Save"
        case .reloadSkills: "Reload Skills"
        case .checkForUpdates: "Check for Skill Updates"
        case .bold: "Bold"
        case .italic: "Italic"
        case .insertLink: "Insert Link"
        case .openInDefaultApp: "Open in Default App"
        case .revealInFinder: "Open in Finder"
        case .showLocations: "Show Skill Locations"
        }
    }

    var group: AppShortcutGroup {
        switch self {
        case .searchSkills, .editView, .readView, .rawView:
            .navigation
        case .newSkill, .installSkill, .reloadSkills, .checkForUpdates:
            .library
        case .save, .bold, .italic, .insertLink:
            .editor
        case .openInDefaultApp, .revealInFinder, .showLocations:
            .selectedSkill
        }
    }

    var defaultShortcut: AppShortcut {
        switch self {
        case .searchSkills: AppShortcut(key: "f", modifiers: [.command, .option])
        case .editView: AppShortcut(key: "1", modifiers: .command)
        case .readView: AppShortcut(key: "2", modifiers: .command)
        case .rawView: AppShortcut(key: "3", modifiers: .command)
        case .newSkill: AppShortcut(key: "n", modifiers: .command)
        case .installSkill: AppShortcut(key: "i", modifiers: [.command, .shift])
        case .save: AppShortcut(key: "s", modifiers: .command)
        case .reloadSkills: AppShortcut(key: "r", modifiers: .command)
        case .checkForUpdates: AppShortcut(key: "u", modifiers: [.command, .shift])
        case .bold: AppShortcut(key: "b", modifiers: .command)
        case .italic: AppShortcut(key: "i", modifiers: .command)
        case .insertLink: AppShortcut(key: "k", modifiers: .command)
        case .openInDefaultApp: AppShortcut(key: "o", modifiers: [.command, .shift])
        case .revealInFinder: AppShortcut(key: "r", modifiers: [.command, .option])
        case .showLocations: AppShortcut(key: "l", modifiers: [.command, .option])
        }
    }
}

struct AppShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    static let control = AppShortcutModifiers(rawValue: 1 << 0)
    static let option = AppShortcutModifiers(rawValue: 1 << 1)
    static let shift = AppShortcutModifiers(rawValue: 1 << 2)
    static let command = AppShortcutModifiers(rawValue: 1 << 3)

    var swiftUIValue: EventModifiers {
        var value: EventModifiers = []
        if contains(.control) { value.insert(.control) }
        if contains(.option) { value.insert(.option) }
        if contains(.shift) { value.insert(.shift) }
        if contains(.command) { value.insert(.command) }
        return value
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var value: AppShortcutModifiers = []
        let flags = eventFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.command) { value.insert(.command) }
        self = value
    }
}

struct AppShortcut: Codable, Hashable, Sendable {
    var key: String
    var modifiers: AppShortcutModifiers

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: modifiers.swiftUIValue)
    }

    var displayName: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += displayKey
        return result
    }

    var hasPrimaryModifier: Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    init(key: String, modifiers: AppShortcutModifiers) {
        precondition(key.count == 1, "A keyboard shortcut must contain exactly one key")
        let normalized = key.lowercased()
        self.key = normalized.count == 1 ? normalized : key
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let modifiers = AppShortcutModifiers(eventFlags: event.modifierFlags)
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        guard let key = characters?.first else { return nil }
        self.init(key: String(key), modifiers: modifiers)
    }

    private var displayKey: String {
        switch key {
        case " ": "Space"
        case "\t": "⇥"
        case "\r", "\n": "↩"
        case "\u{1B}": "Esc"
        case "\u{7F}", "\u{8}": "⌫"
        case "\u{F700}": "↑"
        case "\u{F701}": "↓"
        case "\u{F702}": "←"
        case "\u{F703}": "→"
        default: key.uppercased()
        }
    }
}

enum ShortcutAssignmentIssue: Equatable {
    case needsModifier
    case conflict(AppShortcutAction)

    var message: String {
        switch self {
        case .needsModifier:
            "Include Command, Option, or Control."
        case .conflict(let action):
            "Already used by \(action.title)."
        }
    }
}

@Observable
@MainActor
final class ShortcutSettings {
    private static let storageKey = "keyboard-shortcuts-v1"

    private(set) var overrides: [AppShortcutAction: AppShortcut]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = Self.load(from: defaults)
    }

    func shortcut(for action: AppShortcutAction) -> AppShortcut {
        overrides[action] ?? action.defaultShortcut
    }

    func isCustomized(_ action: AppShortcutAction) -> Bool {
        overrides[action] != nil
    }

    @discardableResult
    func assign(_ shortcut: AppShortcut, to action: AppShortcutAction) -> ShortcutAssignmentIssue? {
        guard shortcut.hasPrimaryModifier else { return .needsModifier }
        if let conflict = AppShortcutAction.allCases.first(where: {
            $0 != action && self.shortcut(for: $0) == shortcut
        }) {
            return .conflict(conflict)
        }

        if shortcut == action.defaultShortcut {
            overrides.removeValue(forKey: action)
        } else {
            overrides[action] = shortcut
        }
        save()
        return nil
    }

    @discardableResult
    func restoreDefault(for action: AppShortcutAction) -> ShortcutAssignmentIssue? {
        if let conflict = AppShortcutAction.allCases.first(where: {
            $0 != action && shortcut(for: $0) == action.defaultShortcut
        }) {
            return .conflict(conflict)
        }
        overrides.removeValue(forKey: action)
        save()
        return nil
    }

    func restoreAllDefaults() {
        overrides.removeAll()
        save()
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [AppShortcutAction: AppShortcut] {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([String: AppShortcut].self, from: data)
        else { return [:] }

        return stored.reduce(into: [:]) { result, item in
            guard let action = AppShortcutAction(rawValue: item.key),
                  item.value.key.count == 1,
                  item.value.hasPrimaryModifier
            else { return }
            result[action] = item.value
        }
    }
}

extension ViewMode {
    var shortcutAction: AppShortcutAction {
        switch self {
        case .edit: .editView
        case .read: .readView
        case .source: .rawView
        }
    }
}

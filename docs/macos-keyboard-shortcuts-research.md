# macOS keyboard shortcuts: recommendation

Last reviewed: **2026-08-27**

## Recommendation

Do **not** use Command-E for Edit. Use a coherent view-mode family instead:

| Mode | Shortcut | Rationale |
| --- | --- | --- |
| Edit | Command-1 | First and default mode |
| Read | Command-2 | Second mode |
| Raw | Command-3 | Third mode |

Apple defines Command-E as **Use Selection for Find** and advises against repurposing standard shortcuts for custom actions. That standard action is relevant here: Skillbook is a text-editing app, and its raw `NSTextView` explicitly enables the native find bar and incremental searching ([Apple HIG: Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards), [`SourceEditor.swift:44-57`](../macos/Skillbook/Views/SourceEditor.swift#L44-L57)). Command-1 through Command-3 follow the macOS precedent of numbered shortcuts for switching among parallel representations; Finder uses the same family for its views ([Apple Support: Mac keyboard shortcuts](https://support.apple.com/en-us/102650)).

The repository defines the modes, in this order, as `Edit`, `Read`, and `Raw` ([`Models.swift:3-7`](../macos/Skillbook/Models.swift#L3-L7)). Preserve both the labels and ordering so the numbered shortcuts are stable and easy to learn.

## Skill search: neither `/` nor Command-K is a safe global shortcut

For a genuinely global **Search Skills** command, use **Option-Command-F**. Apple defines that shortcut as “Jump to the search field control,” whereas Command-F opens Find for the current document ([Apple HIG: Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)). This distinction fits Skillbook: skill search filters the library, while the Edit and Raw modes also need document-local Find. Put **Search Skills** in the View menu with Option-Command-F so the native menu displays the shortcut.

Between the two proposed alternatives, `/` is the less-bad **browse-only accelerator**, but it must not be registered globally:

- A bare `/` is ordinary Markdown and YAML input. A global `.keyboardShortcut("/", modifiers: [])` would compete with typing in both editors. Apple describes app shortcuts as a primary key plus modifiers, recommends Command as the main modifier, and discusses single-key bindings primarily for games ([Apple HIG: Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)).
- Command-K defaults to **Insert Link** in both Markdown editors ([`ShortcutSettings.swift`](../macos/Skillbook/ShortcutSettings.swift)). Reusing it as the default global search command would make the same shortcut perform unrelated actions. A user who prefers Command-K for Search can first rebind Insert Link in Settings, then assign Command-K to Search; duplicate bindings are rejected.

If `/` is still desirable, handle it only while a nonediting browse surface has focus—for example, with `onKeyPress` on the sidebar/list—and return `.ignored` outside that context. Apple documents that `onKeyPress` runs while its view has focus and can either consume the event or allow dispatch to continue ([SwiftUI `onKeyPress`](https://developer.apple.com/documentation/swiftui/view/onkeypress(phases:action:))). Treat `/` as a convenience alias, not the discoverable main-menu shortcut.

### Native focus wiring for macOS 15

Keep the existing SwiftUI `.searchable` field, but add a local Boolean presentation binding:

```swift
@Bindable var model = model

// On the existing sidebar/list hierarchy:
.searchable(
    text: $model.query,
    isPresented: $model.searchPresented,
    placement: .sidebar,
    prompt: "Search skills"
)
```

Apple states that setting `isPresented` activates and focuses the search field on macOS ([Managing search interface activation](https://developer.apple.com/documentation/swiftui/managing-search-interface-activation), [`searchable(text:isPresented:placement:prompt:)`](https://developer.apple.com/documentation/swiftui/view/searchable(text:ispresented:placement:prompt:)-1hn4y)). Skillbook's current command closure can set the shared model binding directly. If the app later gives each window an independent model, publish the focus action through `focusedSceneValue` and read it from a small `Commands` type with `@FocusedValue`; Apple documents that pattern for routing commands to the active scene ([`focusedSceneValue`](https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:)-57boz), [Building and customizing the menu bar with SwiftUI](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui)).

The existing `isPresented` overload remains appropriate for Skillbook's macOS 15 deployment target ([`project.yml:3-18`](../macos/project.yml#L3-L18)). `searchFocused` is also available when a future interaction needs explicit focus-state observation; the current command only needs to present and focus search.

## Native menu wiring

Make the macOS **View** menu the canonical discoverability surface:

1. Add the three mode actions in `SkillbookApp.commands` with `CommandGroup(after: .sidebar)` and apply `.keyboardShortcut("1")` through `.keyboardShortcut("3")` to their controls. `CommandGroup` adds items to a standard menu location; `.sidebar` is the placement for View-menu sidebar/full-screen commands ([Apple: `CommandGroup`](https://developer.apple.com/documentation/swiftui/commandgroup), [Apple: `.sidebar` placement](https://developer.apple.com/documentation/swiftui/commandgroupplacement/sidebar)). Do not create `CommandMenu("View")`: Apple documents that `CommandMenu` creates a separate top-level custom menu after the built-in View menu ([Apple: `CommandMenu`](https://developer.apple.com/documentation/swiftui/commandmenu)).
2. Add `SidebarCommands()` if the app does not already get a working Show/Hide Sidebar command. Apple explicitly recommends it when a scene has a navigation sidebar ([Apple: Building and customizing the menu bar with SwiftUI](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui), [Apple: `SidebarCommands`](https://developer.apple.com/documentation/swiftui/sidebarcommands)).
3. Move `Reload Skills` and `Update All…` out of the existing `CommandGroup(after: .sidebar)` and into the existing **Skill** `CommandMenu`; they are Skill actions, not View/sidebar actions. The current placement is at [`SkillbookApp.swift:45-73`](../macos/Skillbook/SkillbookApp.swift#L45-L73).

Apple says macOS toolbar commands must also be available in the menu bar because toolbars can be hidden or customized ([Apple HIG: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)). The View-menu commands therefore should own discoverability even if the toolbar control changes later.

## Toolbar menu and shortcut hints

Replace the current toolbar `Picker(...).pickerStyle(.menu)` with a `Menu` whose three items are actionable controls and attach the same `.keyboardShortcut` values to them. SwiftUI renders controls inside `Menu` as actionable menu items, and `keyboardShortcut` assigns the key equivalent to a control ([Apple: Populating SwiftUI menus with adaptive controls](https://developer.apple.com/documentation/swiftui/populating-swiftui-menus-with-adaptive-controls), [Apple: `keyboardShortcut(_:)`](https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:))). This is the native route to showing the Command-1 … Command-3 glyphs next to the toolbar menu items; do not hard-code glyph text such as `"⌘1"` into labels.

Both the toolbar menu items and main-menu commands should call the same small `viewMode` mutation. Duplicate key equivalents are acceptable only because they perform the identical action: SwiftUI resolves shortcuts in the key window before command groups, and uses the first matching control ([Apple: `keyboardShortcut(_:)`](https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:))). Keep the main-menu commands even if the toolbar copy resolves first.

Preserve a visible current-mode indication in the toolbar menu. Apple describes menu choices as commands or states and recommends clearly representing the currently selected state; keep the existing picker behavior or reproduce its checkmark when moving to actionable items ([Apple HIG: Menus](https://developer.apple.com/design/human-interface-guidelines/menus)).

## Existing shortcut inventory

The app already owns these shortcuts in [`SkillbookApp.swift`](../macos/Skillbook/SkillbookApp.swift) and [`ShortcutSettings.swift`](../macos/Skillbook/ShortcutSettings.swift): Command-N New Skill, Shift-Command-I Install Skill, Command-S Save, Command-B Bold, Command-I Italic, Command-K Insert Link, Shift-Command-O Open in Default App, Option-Command-R Open in Finder, Option-Command-L Show Skill Locations, Command-R Reload Skills, and Shift-Command-U Update All. The proposed Command-1 through Command-3 family does not collide with them. The toolbar also repeats Command-S on Save ([`DetailView.swift`](../macos/Skillbook/Views/DetailView.swift)); because both copies save, this follows the same resolution rule but remains worth covering in a shortcut smoke test.

## User overrides

Expose app-defined shortcuts in a **Shortcuts** tab in the native Settings scene. Apple describes keyboard mappings as an appropriate example of a general, infrequently changed preference, and recommends keeping the set of settings focused ([Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Apple HIG: Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)). The panel therefore covers the app's menu commands without duplicating system-managed shortcuts such as Quit or Settings.

Use an AppKit responder-backed recorder so Command combinations are captured before the menu dispatches them. `NSEvent.charactersIgnoringModifiers` (or `characters(byApplyingModifiers:)`) provides a hardware-independent base key, and a local event monitor can consume the event only while recording ([Apple: `charactersIgnoringModifiers`](https://developer.apple.com/documentation/appkit/nsevent/charactersignoringmodifiers), [Apple: `NSEvent`](https://developer.apple.com/documentation/appkit/nsevent)). Persist the binding as a key plus semantic modifier flags, then construct SwiftUI `KeyboardShortcut` values at the point of use so macOS continues to render and localize the menu equivalent.

Reject duplicate app bindings with an inline error, require Command, Option, or Control to avoid stealing ordinary text input, and provide both per-command and global restore controls. Changes should apply immediately; restarting the app must preserve them.

## Focused-state scope

The current app has one shared `AppModel` and one `WindowGroup`, so its existing direct model capture in `SkillbookApp.commands` is sufficient for this change ([`SkillbookApp.swift:19-33`](../macos/Skillbook/SkillbookApp.swift#L19-L33), [`AppModel.swift:11-23`](../macos/Skillbook/AppModel.swift#L11-L23)). If the app later supports independent per-window models, route command state through `FocusedValues`; Apple uses focused values to connect the active scene/view to menu commands ([Apple tutorial: Creating a macOS app](https://developer.apple.com/tutorials/swiftui/creating-a-macos-app), [WWDC23: The SwiftUI cookbook for focus](https://developer.apple.com/videos/play/wwdc2023/10162/)). That refactor is not needed for the current single-window model.

## Validation checklist

- With text selected in Edit and Raw, Command-E still performs **Use Selection for Find**.
- Command-1 through Command-3 switch modes from both editor and sidebar focus.
- Option-Command-F focuses **Search skills** from sidebar, preview, Edit, and Raw focus without clearing the current query.
- Typing `/` in Edit or Raw inserts `/`; any browse-only `/` alias activates search only when its browse surface has focus.
- Command-K invokes **Insert Link** in both Markdown editors until the user rebinds it.
- The built-in View menu shows all three commands and native shortcut glyphs.
- The toolbar View menu shows the current mode and the same glyphs.
- Disabled/empty-selection behavior is identical whether a command is invoked by click or key.
- Command-S, Command-R, and the existing Shift/Option shortcuts still invoke their original actions.

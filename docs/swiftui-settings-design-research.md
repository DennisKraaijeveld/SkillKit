# SwiftUI settings design research for Skillbook

## Executive recommendation

Keep Skillbook's native SwiftUI `Settings` scene, but replace the single long settings form with two stable, toolbar-style panes:

1. **Sources** — project folder, additional folders, and automatically detected agent folders.
2. **Appearance** — System, Light, or Dark.

The result should feel like a compact Mac utility, not a miniature website: standard controls, system typography and colors, one clear action per row, technical paths as secondary information, and no decorative cards or custom window chrome. Apple explicitly recommends the Settings scene and Command-Comma convention, says Mac settings windows commonly use a noncustomizable toolbar to switch among related panes, and advises minimizing the number of settings offered. SwiftUI's `Settings` documentation specifically supports a `TabView` for grouping settings collections. ([Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [SwiftUI `Settings`](https://developer.apple.com/documentation/swiftui/settings))

This is not an argument for making every small group a tab. Two panes are justified because the current screen mixes two different mental models—where Skillbook searches and how it looks—and because the long read-only directory inventory currently overwhelms the actual controls. Do not add more panes until there is a genuinely distinct group of settings.

## What the current implementation gets right

- `SkillbookApp.swift:76-80` already uses SwiftUI's `Settings` scene, so the app gets the standard application-menu entry and Command-Comma behavior from the system.
- `SettingsView.swift:14-89` uses a native `Form` with grouped styling. SwiftUI applies platform-appropriate control styling and accessibility behavior to forms, while `GroupedFormStyle` supplies scrolling and aligned rows. ([SwiftUI `Form`](https://developer.apple.com/documentation/swiftui/form), [`GroupedFormStyle`](https://developer.apple.com/documentation/swiftui/groupedformstyle))
- The System/Light/Dark segmented picker is a suitable control for three closely related, mutually exclusive choices. Apple's segmented-control guidance says this control is useful when the grouping and current selection should be clear at a glance, while cautioning against too many segments. ([Apple HIG: Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls))
- Folder selection uses the system file importer rather than a custom browser. This preserves familiar keyboard, navigation, and access behavior. ([SwiftUI `fileImporter`](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)))
- Found/missing is expressed in text, not color alone, and existing folders offer a direct Open in Finder action.
- The backend validates the project folder as a directory and rejects a missing additional folder (`crates/skillbook-ffi/src/lib.rs:428-459`). That domain validation should remain authoritative.

## Current usability and trust gaps

### 1. Settings, status, and diagnostics are visually equal

The original screenshot shows five equally prominent grouped sections. Two are editable preferences, two are source-management workflows, and one is a read-only diagnostic list. The seven global directory rows dominate the window even though people cannot change them. As a result, the primary actions—choose a project folder, add another folder, or change appearance—are harder to scan.

Apple's current guidance is to minimize settings and to keep task-specific options near the task they affect. Empirical menu studies also find faster search when choices are categorically organized and when order remains stable; changing menus or item order impairs knowledge-driven search. These studies concern menus rather than settings windows, so they support the grouping principle, not a specific visual treatment. ([Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Vandierendonck, Van Hoe & De Soete, 1988](https://doi.org/10.1016/0001-6918(88)90034-0), [McDonald, Molander & Noel, CHI 1988](https://doi.org/10.1145/57167.57183))

### 2. The source hierarchy is implementation-first

Phrases such as “Project scan directory,” “Walk this folder,” “well-known agent directories,” and “the rest” describe internal mechanics. A person mainly needs to know which locations Skillbook searches and what will happen after choosing one. Full absolute paths are useful to this technical audience, but they should support the folder name and status rather than become the largest text in each row.

### 3. A failed Settings action has no Settings-local presentation

`SettingsView.pick` discards every failed importer result (`SettingsView.swift:99-104`). Backend errors are assigned to the shared `AppModel.error` (`AppModel.swift:374-430`), but that error is rendered only by `WorkspaceView`, not by the settings window. A person can therefore paste an invalid path or encounter a save failure in Settings and receive no feedback in the window where the action occurred.

Apple describes feedback as the mechanism that communicates current state, success or failure, and warnings. Alerts should use specific titles and concise recovery-oriented text, but a nonblocking field error is better kept inline beside the field so the person can correct it without modality. ([Apple HIG: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Apple HIG: Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts))

### 4. Window sizing and appearance are only partly propagated

`SkillbookApp.swift:79` forces every setting into a 520 × 620 point content frame. Apple's Mac guidance says a settings window normally accommodates the current pane, and SwiftUI can size tabbed settings content by pane. Give panes a consistent intrinsic width but content-appropriate height; cap and scroll only the variable-length Sources pane. ([Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings))

The main window receives `.preferredColorScheme(model.colorScheme)`, but the Settings scene does not. Apply the same modifier to Settings so choosing Light or Dark visibly and consistently affects the window containing the control.

## Proposed information architecture

| Pane | Content | Why it belongs there |
| --- | --- | --- |
| **Sources** (`folder`) | Project folder, additional folders, detected agent folders | Everything answers one question: “Where does Skillbook look for skills?” |
| **Appearance** (`circle.lefthalf.filled`) | System, Light, Dark | A small but clearly understood category; the selected pane can remain compact. |

Use a stable order and restore the last selected pane. On first use, open **Sources**, because it is the only pane that changes what appears in Skillbook. The current HIG asks Mac apps to restore the most recently viewed settings pane, and both Apple docs and empirical menu research support a stable, learnable organization. ([Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Gaspar-Figueiredo et al., 2025](https://doi.org/10.1016/j.jss.2025.112598))

The 2025 study tested adaptive graphical menus, including a browser-settings scenario, and found that changing visual properties generally increased cognitive load and memorization demand versus a static baseline. It does not prove a universal rule for every settings screen, but it is a useful warning against reordering panes, promoting “frequent” settings, or animating categories based on behavior.

## Recommended Sources pane

### Project folder

Present one labeled row:

- Label: **Project folder**
- No selection: **Not set** in secondary text, with **Choose…** as the primary row action.
- Selection: folder name as primary text; the full selectable path beneath it in a smaller monospaced style; **Change…** and a secondary **Remove** action.
- Help text: “Finds skills inside `.claude`, `.cursor`, and other supported agent folders in this project.”

Use `LabeledContent` rather than hand-built spacer alignment. It associates a label with its value, adapts to form context, and preserves the label's semantic/accessibility role. ([SwiftUI `LabeledContent`](https://developer.apple.com/documentation/swiftui/labeledcontent))

Configure the system chooser with a meaningful confirmation label and message, for example **Choose Folder** and “Choose the project Skillbook should scan for agent skill folders.” SwiftUI exposes `fileDialogConfirmationLabel`, `fileDialogMessage`, `fileDialogDefaultDirectory`, and `fileDialogCustomizationID` for this purpose. ([SwiftUI `fileDialogDefaultDirectory`](https://developer.apple.com/documentation/swiftui/view/filedialogdefaultdirectory(_:)), [SwiftUI `fileImporter`](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)))

The existing access calls need one correction if sandboxing is enabled later: call `stopAccessingSecurityScopedResource()` only when `startAccessingSecurityScopedResource()` returned `true`, and persist security-scoped bookmark data if Skillbook needs access after the chooser callback. Apple requires balanced start/stop access and notes that access ends immediately after the final stop. The current app has App Sandbox disabled, but the UI flow should not bake in a future sandbox failure. ([Foundation `startAccessingSecurityScopedResource`](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()))

### Additional folders

Show a compact list below **Additional folders**:

- Each row uses the folder name as the primary label and the full path as selectable secondary text.
- Each row has **Open in Finder** and **Remove**. Text labels are preferable while there is space; if icon-only buttons are used, use SF Symbols, explicit accessibility labels, and `.help` tooltips.
- Empty state: “No additional folders” plus **Add Folder…**. Keep it compact inside Settings; reserve a full `ContentUnavailableView` for a main-window empty state where it can pair explanation with a call to action. ([SwiftUI `ContentUnavailableView`](https://developer.apple.com/documentation/swiftui/contentunavailableview))
- Make browsing the primary add path. Keep “Enter a path manually” as one disclosure, because pasted paths are valuable to developer users but are not the safest default path. Apple recommends placing disclosure controls next to the content they reveal and avoiding multiple disclosures in one view. ([Apple HIG: Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls), [SwiftUI `DisclosureGroup`](https://developer.apple.com/documentation/swiftui/disclosuregroup))
- The manual path row needs a visible **Add** button as well as Return support. Disable Add for an empty or unchanged value. If validation fails, keep the entered path and show “That folder doesn't exist” directly below the row.

Removing a scan location does not delete its files, so a confirmation alert would add friction without protecting data. Make the label precise—**Remove from Skillbook** in a menu or accessibility hint if “Remove” could be mistaken for deletion—and consider a brief Undo action only if users remove locations often.

### Detected agent folders

Start with a summary such as **Detected agent folders — 3 of 7 available**. Put the full inventory behind one disclosure because it is diagnostic, not a preference. This is progressive disclosure of secondary status, not hidden essential functionality.

Expanded rows should show:

- A human-readable agent name (`Claude`, `Cursor`, `Codex`) rather than lowercase backend identifiers.
- The absolute path as secondary, selectable monospaced text.
- A symbol plus text: `checkmark.circle` **Available** or `minus.circle` **Not found**.
- **Open in Finder** only for available folders.

Do not dim “Not found” to near-invisibility and do not use red/green alone. Apple's accessibility guidance requires information to remain perceivable without relying on one method, and its color guidance recommends semantic system colors that adapt to light, dark, and Increase Contrast settings. A controlled CHI study found no support for color-coding as the identifier for menu categories; structure and labels should do the work. ([Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color), [McDonald, Molander & Noel, CHI 1988](https://doi.org/10.1145/57167.57183))

## Recommended Appearance pane

Keep the current three-segment control. The polish comes from context and correctness rather than decoration:

- Label: **Appearance**
- Values: System, Light, Dark
- Help text: “System follows the appearance selected in macOS.”
- Apply the choice immediately to both the main and settings windows.
- If persistence fails, restore the previous value and show the error in this pane. The current model changes `appearance` before awaiting the backend and does not roll it back on failure (`AppModel.swift:424-430`).

Use system text styles and colors rather than custom font sizes or hard-coded grays. Apple's macOS typography guidance identifies SF Pro as the system font, recommends built-in text styles, and sets 13 pt as the default and 10 pt as the minimum for Mac text. System colors adapt across appearance and accessibility contrast settings. ([Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color))

## Flow outside the Settings window

> Decision update: Skillbook now requires a focused first-launch setup before entering the workspace. It detects global agent folders automatically, then asks the user to choose work and additional skill folders or explicitly accept detected folders only. The contextual folder guidance below still applies after setup.

When there is no project folder and the current main-window context would benefit from one, offer a contextual **Choose Project Folder…** action in the main empty state or source-area menu. It should invoke the same source mutation as Settings. This follows Apple's guidance to keep task-specific options close to the task instead of making people leave their work to find them. ([Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings))

A good source-change flow is:

1. Choose a folder with the system file dialog.
2. Validate it before replacing the current source.
3. Show progress in the affected row while Skillbook rescans.
4. On success, update the path and optionally report a concrete result such as “12 skills found.”
5. If no supported skill folders are found, keep the selected project but explain the result; an empty project can become valid later.
6. On failure, retain the previous source and put recovery text beside the control.

Avoid a celebratory modal or animation. The visible updated path, status, and skill count are sufficient feedback.

## SwiftUI structure

The following is an architectural sketch, not a drop-in patch. Skillbook's Rust-backed configuration should remain the domain source of truth; `AppStorage` is appropriate only for the selected UI pane if desired.

```swift
private enum SettingsPane: String {
    case sources
    case appearance
}

struct SettingsRootView: View {
    @AppStorage("settings.selectedPane")
    private var selection = SettingsPane.sources.rawValue

    var body: some View {
        TabView(selection: $selection) {
            SourcesSettingsView()
                .tabItem { Label("Sources", systemImage: "folder") }
                .tag(SettingsPane.sources.rawValue)

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .tag(SettingsPane.appearance.rawValue)
        }
    }
}
```

Apple documents both a single settings view and a `TabView` of settings collections. `Label` plus SF Symbols provides consistent alignment, weight, appearance adaptation, and accessible text. ([SwiftUI `Settings`](https://developer.apple.com/documentation/swiftui/settings), [Apple HIG: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols))

For short panes, a columns form gives the classic Mac relationship between labels and values:

```swift
Form {
    LabeledContent("Appearance") {
        Picker("Appearance", selection: $appearance) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }
}
.formStyle(.columns)
```

`ColumnsFormStyle` is non-scrolling and aligns a trailing label column with a leading value column. The variable-height Sources pane should instead use grouped form/list content with scrolling. ([SwiftUI `ColumnsFormStyle`](https://developer.apple.com/documentation/swiftui/columnsformstyle), [`GroupedFormStyle`](https://developer.apple.com/documentation/swiftui/groupedformstyle))

Do not replace these controls with custom clickable `HStack`s. Apple's WWDC24 accessibility session recommends built-in controls and the SwiftUI styling system because they retain labels, traits, states, and actions automatically; custom controls require recreating that accessibility behavior. ([WWDC24: Catch up on accessibility in SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10073/))

## State, validation, and error behavior

Each independently saved setting should have local operation state:

| State | Presentation | Interaction |
| --- | --- | --- |
| Idle | Current value and normal actions | Enabled |
| Editing | Draft remains visible | Save/Add enabled only when valid and changed |
| Saving/scanning | Inline `ProgressView` and action-specific text | Disable only the affected action |
| Success | Updated value plus brief textual confirmation | Return to idle without blocking |
| Failure | Specific inline message and retry path | Preserve the draft and previous committed value |

Concrete rules:

- The Rust backend remains authoritative for path existence and persistence errors. SwiftUI can do cheap empty/duplicate checks to guide the control, but must render backend failures.
- Do not clear `pastedPath` until `addCustomRoot` succeeds. The current code clears it immediately after dispatch (`SettingsView.swift:58-64`), which removes the evidence a person needs to correct a failed path.
- Treat file-dialog cancellation as neutral. The `fileImporter` documentation notes that cancellation dismisses the dialog without invoking the completion closure; do not display an error for it.
- Handle actual importer failures rather than dropping them.
- Use an alert only when a decision interrupts the flow or protects against consequential action. Field validation and ordinary save failures belong inline. If an alert is necessary, use a specific title such as **Couldn't Add Folder**, not **Error**, and label the recovery action directly. ([Apple HIG: Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts))
- Changes should persist at the moment their individual action completes. Do not rely on settings-window dismissal, because users can close or quit at any time. Apple's archived Preference Pane guide also recommends saving each change when practical rather than waiting for the pane to close; use it as historical Mac behavior context, not as current SwiftUI API authority. ([Apple Preference Pane Programming Guide: Managing User Preferences](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/PreferencePanes/Concepts/Managing.html))

## Accessibility requirements

1. **Use native controls first.** `Button`, `Picker`, `SecureField`, `DisclosureGroup`, `Form`, and `LabeledContent` already expose basic accessibility semantics. Add modifiers to improve context, not to repair avoidable custom controls. ([SwiftUI accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals))
2. **Make every action self-identifying.** VoiceOver should hear “Open Claude skill folder in Finder,” not several identical “Open in Finder” buttons without row context. Use `.accessibilityLabel` and, when useful, a short `.accessibilityHint` describing the result. ([SwiftUI accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility), [`accessibilityHint`](https://developer.apple.com/documentation/swiftui/view/accessibilityhint(_:)))
3. **Expose status as a value.** A directory row can announce label “Claude skill folder,” value “Available” or “Not found,” and then the Open in Finder action. Do not make the icon a separate stop.
4. **Do not rely on color.** Pair every status color with text and a symbol. Verify light, dark, and Increase Contrast. Apple's audit guidance includes contrast, hit region, description, hierarchy, and action checks. ([Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Performing accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app))
5. **Keep important text legible.** Avoid `.tertiary` for required state such as Not found, especially at caption size. Use secondary styling for supporting paths and keep full paths selectable with middle truncation or a tooltip rather than making the entire window wider indefinitely.
6. **Maintain comfortable targets.** Native regular-size controls satisfy the platform defaults; Apple's current guidance lists 28 × 28 pt as the default Mac control size and 20 × 20 pt as the minimum. Do not shrink plus/minus/Open in Finder buttons to decorate dense rows. ([Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility))
7. **Support keyboard-only use.** Test logical traversal order, activation, Return on manual Add, Escape in dialogs, and the system Command-Comma shortcut with Full Keyboard Access enabled. ([Apple HIG: Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards))
8. **Use tooltips for compact buttons, not for essential instructions.** Apple's Mac guidance recommends context-sensitive help for a specific control via SwiftUI's `.help`, while warning that a control needing a long explanation probably needs simplification. ([Apple HIG: Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help))

## Visual polish checklist

- Keep the platform title bar and traffic-light behavior supplied by `Settings`; do not recreate a custom panel.
- Use a consistent pane width based on real path-content testing; 520 points is a reasonable starting width, not a hard requirement. Give the Sources pane bounded scrolling rather than a fixed 620-point height for every pane.
- Let `Form`, `LabeledContent`, and native control styles own alignment and spacing. Avoid another layer of rounded backgrounds inside grouped form sections.
- Use system text styles: headline only for section identity, body for labels, caption/secondary for full paths and explanatory copy.
- Use SF Symbols only where they reinforce meaning. Keep text on the two pane icons and on unfamiliar actions.
- Capitalize user-facing agent names. Keep filesystem spelling only in paths.
- Prefer one concise sentence of help per group. Long paragraphs and implementation phrases make a small settings window feel heavier than it is.
- Show selected values and effective state; beauty here comes from calm hierarchy and certainty, not gradients, glass, or animation.

## Suggested copy

| Current | Recommended |
| --- | --- |
| Project scan directory | Project folder |
| Walk this folder for .cursor/skills, .claude/skills, and the rest. | Finds skills inside `.claude`, `.cursor`, and other supported agent folders in this project. |
| Global skill folders | Detected agent folders |
| Well-known agent directories. Skillbook lists them even when they are missing. | Skillbook checks these agent folders automatically. |
| found / missing | Available / Not found |
| Custom folders | Additional folders |
| Drop a folder on the window, paste a path, or choose one. | Scan folders outside the project and detected agent locations. |
| Add folder… | Add Folder… |
| Clear | Remove |

## Validation plan

### Functional scenarios

- No project folder, no additional folders, some detected global folders.
- Project folder chosen successfully; rescanning in progress; scan completes with skills; scan completes with none.
- Invalid pasted path; duplicate path; path disappears after it was saved.
- File chooser cancellation and a real importer failure.
- Zero, one, and many additional folders, including paths long enough to truncate.
- Appearance persistence success and failure; all three appearances reflected in both windows.

### Accessibility and visual scenarios

- VoiceOver traversal and action names for every pane and every directory row.
- Full Keyboard Access from pane selection through every control.
- Accessibility Inspector audit for each pane and its failure state.
- XCTest UI coverage using `performAccessibilityAudit()` for Sources and Appearance. Apple says the automated audit fails on detected issues and checks the current screen in the same manner as Accessibility Inspector. ([WWDC23: Perform accessibility audits for your app](https://developer.apple.com/videos/play/wwdc2023/10035/), [Performing accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app))
- Light, dark, Increase Contrast, Reduce Transparency, and at least 1× and 2× display scaling.
- Narrow/long localized labels and long home-directory paths.

## Implementation priority

### P0 — trust and correctness

1. Surface Settings errors and progress in Settings.
2. Preserve draft input on failure.
3. Apply appearance to the Settings window and roll back on persistence failure.

### P1 — information architecture and native layout

1. Introduce the two stable `TabView` panes.
2. Rebuild rows with `LabeledContent` and clear primary/secondary text hierarchy.
3. Collapse the detected-directory inventory to a summary plus one disclosure.
4. Replace the universal fixed height with content-appropriate pane sizing.

### P2 — polish and verification

1. Refine copy and agent capitalization.
2. Add pane-aware accessibility labels, values, hints, and help tags.
3. Configure file-dialog labels, message, and remembered directory.
4. Add previews for every major state and automate accessibility audits.

## Sources

### Primary Apple design and implementation guidance

- [Human Interface Guidelines — Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Human Interface Guidelines — Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Human Interface Guidelines — Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [Human Interface Guidelines — Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Human Interface Guidelines — Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Human Interface Guidelines — Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)
- [Human Interface Guidelines — Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)
- [Human Interface Guidelines — Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help)
- [Human Interface Guidelines — Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- [Human Interface Guidelines — Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)
- [SwiftUI `Settings`](https://developer.apple.com/documentation/swiftui/settings)
- [Adding a settings interface to your app](https://developer.apple.com/documentation/foundation/adding-a-settings-interface-to-your-app)
- [SwiftUI `Form`](https://developer.apple.com/documentation/swiftui/form)
- [SwiftUI `GroupedFormStyle`](https://developer.apple.com/documentation/swiftui/groupedformstyle)
- [SwiftUI `ColumnsFormStyle`](https://developer.apple.com/documentation/swiftui/columnsformstyle)
- [SwiftUI `LabeledContent`](https://developer.apple.com/documentation/swiftui/labeledcontent)
- [SwiftUI `DisclosureGroup`](https://developer.apple.com/documentation/swiftui/disclosuregroup)
- [SwiftUI `ContentUnavailableView`](https://developer.apple.com/documentation/swiftui/contentunavailableview)
- [SwiftUI `fileImporter`](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:))
- [Foundation security-scoped resource access](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource())
- [WWDC24 — Catch up on accessibility in SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10073/)
- [WWDC23 — Perform accessibility audits for your app](https://developer.apple.com/videos/play/wwdc2023/10035/)
- [Performing accessibility audits for your app](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)

### Original research

- Vandierendonck, A., Van Hoe, R., & De Soete, G. (1988). [Menu search as a function of menu organization, categorization and experience](https://doi.org/10.1016/0001-6918(88)90034-0). *Acta Psychologica, 69*(3), 231–248.
- McDonald, J. E., Molander, M. E., & Noel, R. W. (1988). [Color-coding categories in menus](https://doi.org/10.1145/57167.57183). *Proceedings of CHI '88*, 101–106.
- Gaspar-Figueiredo, D. et al. (2025). [User experience with adaptive user interfaces: Comparing performance and preferences](https://doi.org/10.1016/j.jss.2025.112598). *Journal of Systems and Software*.
- Forsey, H. et al. (2024). [Designing for Learnability: Improvement Through Layered Interfaces](https://doi.org/10.1177/10648046241273291). *Ergonomics in Design*. This study offers tentative support for progressive disclosure in a complex interface and explicitly reports substantial individual differences; it should not be used to hide core settings.

### Practitioner implementation references — secondary, not design authority

- Natalia Panferova, Nil Coalescing (2024): [Scene types in a SwiftUI Mac app](https://nilcoalescing.com/blog/ScenesTypesInASwiftUIMacApp/). Useful as a concise demonstration of the `Settings` scene; Apple's documentation remains authoritative.
- Genji App Blog (2022): [Aligning macOS settings items with `LabeledContent`](https://genjiapp.com/blog/2022/10/31/swiftui-align-setting-items.html). Useful implementation evidence for native label/value alignment.
- Sarah Reichelt, TrozWare (2024): [SwiftUI for Mac 2024](https://troz.net/post/2024/swiftui-mac-2024/). Useful practitioner observations about Mac-specific SwiftUI tab behavior; validate details against the current deployment target and Apple docs.

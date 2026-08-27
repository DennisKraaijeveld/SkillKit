---
target: attached Skillbook Settings screen
total_score: 22
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 4
timestamp: 2026-08-26T16-03-36Z
slug: macos-skillbook-settings-settingsview-swift
---
Method: dual-agent (A: /root/design_assessment · B: /root/detector_assessment)

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---:|---|
| 1 | Visibility of system status | 2/4 | Settings mutations have no progress, success, or error feedback in the Settings window. |
| 2 | Match system / real world | 3/4 | The developer context is appropriate, but “walk,” “the rest,” and “field commits” expose implementation language. |
| 3 | User control and freedom | 2/4 | Folder controls can be reversed, but removal is immediate and token saving on blur is surprising. |
| 4 | Consistency and standards | 2/4 | Native controls are familiar, but appearance can differ between app scenes and the advertised drop interaction is absent here. |
| 5 | Error prevention | 2/4 | File picking constrains input, but pasted paths and repeated asynchronous actions have weak guardrails. |
| 6 | Recognition rather than recall | 3/4 | Paths and statuses are visible; token precedence and drag/drop location still have to be remembered. |
| 7 | Flexibility and efficiency | 3/4 | Browse, paste, reveal, and app-level drop paths exist, although their presentation is inconsistent. |
| 8 | Aesthetic and minimalist design | 2/4 | The screen is quiet, but seven read-only diagnostic rows bury three editable groups. |
| 9 | Error recognition and recovery | 1/4 | Failures are rendered only in the workspace window, often behind Settings; importer failures are discarded. |
| 10 | Help and documentation | 2/4 | Helper copy exists, but some is vague, technical, or promises behavior this window lacks. |
| **Total** | | **22/40** | **Acceptable; significant usability improvements remain.** |

## Design Specificity Verdict

**LLM assessment:** Functional but category-interchangeable. The view looks like a default grouped form populated with Skillbook data rather than an authored expression of Skillbook's core model: where skills come from, which sources are active, and whether authentication is working. The product-specific material is already present, but the screen gives every section and directory row roughly equal weight.

**Deterministic scan:** The detector returned zero primary and zero advisory findings for `SettingsView.swift`. That is not a native-UI clean bill of health: the detector's rule set is built for HTML/CSS/JavaScript and has no SwiftUI semantic or rendered-layout coverage. It produced no false positives, but manual inspection found below-fold discoverability, missing local async feedback, silent importer failures, implicit submissions, long-path risk, and possible cross-scene appearance mismatch.

**Visual evidence:** Browser overlays were not applicable because this is a native macOS SwiftUI scene, not a DOM surface. No user-visible overlay was created. The attached 2336×1792 screenshot and source were reviewed instead.

## Overall Impression

The native foundation is correct and worth preserving. The biggest opportunity is not decoration; it is to turn a long diagnostic form into a compact, stable, confidence-building Mac settings experience. Beauty here comes from calm hierarchy, precise copy, aligned native controls, and unmistakable state.

## What's Working

1. `Settings`, `Form`, `Section`, `SecureField`, `fileImporter`, and standard buttons establish a familiar macOS interaction baseline.
2. Project, automatic, and additional sources are already separated semantically, and monospaced paths fit the technical audience.
3. Direct Choose, Reveal, Remove, and appearance controls avoid unnecessary dialogs.

## Research-backed Direction

Keep the system Settings scene and introduce three stable panes:

| Pane | Contents | Purpose |
|---|---|---|
| **Sources** | Project folder, additional folders, detected agent folders | Answers “Where does Skillbook look?” |
| **GitHub** | Effective credential source, saved credential, save/remove/status | Makes authentication understandable and trustworthy. |
| **Appearance** | System, Light, Dark | Keeps the small visual preference distinct and immediate. |

Use `TabView` with `tabItem` for this repository's macOS 14 target; the newer `Tab` declaration starts at macOS 15. Persist the selected pane and let normal Settings entry restore it. Deep-link “Add GitHub token…” to GitHub and missing-project actions to Sources. Keep task-specific folder selection inside the Install flow so people do not have to leave the task merely to satisfy a prerequisite.

Within panes, use `LabeledContent` for label/value alignment, a compact summary plus one `DisclosureGroup` for the read-only detected inventory, and local state for idle/editing/saving/success/failure. Keep a consistent intrinsic width around the current 520 points, but remove the universal 620-point height; only the variable Sources pane should have bounded scrolling.

Do not add custom glass, gradients, or decorative nested cards. Current Apple guidance favors stable toolbar panes for macOS settings, and SwiftUI's own Settings documentation and current Apple sample use `TabView`, native `Form`, and content-driven sizing. Product character can come from human-readable provider names and restrained existing provider marks inside source rows, not from replacing system controls.

## Priority Issues

### [P1] Settings actions provide feedback in the wrong window

**Why it matters:** Folder and token mutations write errors and success to shared state rendered only by `WorkspaceView`. The settings window can obscure that surface, so the user sees no response where the action happened. Token saving on Return or focus loss makes this especially ambiguous.

**Fix:** Give each setting an explicit local operation state. Disable only the affected action, preserve drafts on failure, show short inline success, and place specific recovery text beside the control. Handle importer failures; keep cancellation neutral.

**Suggested command:** `/impeccable harden`

### [P1] The information architecture lets diagnostics dominate configuration

**Why it matters:** Seven automatic directory rows consume the first viewport and push Additional folders, GitHub, and Appearance below the fold. Users opening Settings to make a change first encounter information they cannot edit.

**Fix:** Move to Sources, GitHub, and Appearance panes. In Sources, show “3 of 7 available,” list active sources first, and collapse unavailable/full diagnostic inventory behind one disclosure. Restore the last pane and route contextual entry points to the relevant pane.

**Suggested command:** `/impeccable layout`

### [P1] GitHub access is visually masked but operationally opaque and stored in plaintext

**Why it matters:** The screen does not say whether `GITHUB_TOKEN`, `GH_TOKEN`, or the saved value is actually active. It preloads the stored secret into view state and saves on blur. The Rust config serializes the token into `config.toml`; a `SecureField` masks display but does not secure storage.

**Fix:** Show Current source separately from Saved token. Use a blank replacement field with explicit Save Token and Remove Saved Token actions, inline status, and Keychain-backed storage. Do not claim verification unless Skillbook performs an authenticated request.

**Suggested command:** `/impeccable harden`

### [P1] Folder entry promises and commit behavior are inconsistent

**Why it matters:** “Drop a folder on the window” appears in Settings, but only the main workspace implements `.onDrop`. The pasted-path field commits only on Return, while the visible Add Folder button opens a picker. Both paths can look broken.

**Fix:** Make browsing the primary Add Folder action. Put manual path entry behind a small disclosure with a visible Add button and inline validation. Either implement an actual Settings drop target with hover feedback or explicitly name the main Skillbook window. In the Install sheet, allow Choose Project Folder inline and continue the task after success.

**Suggested command:** `/impeccable clarify`

### [P2] Scene consistency, accessibility context, and path resilience need a native QA pass

**Why it matters:** The main scene applies the selected color scheme but the Settings scene does not. Repeated “Reveal,” “Remove,” and “Clear” labels are weak when VoiceOver navigates actions directly. `.tertiary` caption statuses are faint, and arbitrary full paths have no truncation or copy policy.

**Fix:** Apply appearance to both scenes and roll back if persistence fails. Give actions row-specific accessibility labels, expose availability as an accessibility value, pair symbol with text, avoid tertiary styling for required state, and test long paths, localization, Increase Contrast, Full Keyboard Access, and VoiceOver.

**Suggested command:** `/impeccable audit`

## Persona Red Flags

**Jordan (first-timer):** “Walk this folder” and “the rest” assume hidden-directory knowledge. The explicit drop instruction fails in this window, and a successful chooser action never produces a clear “scanning” or “skills found” ending.

**Sam (accessibility-dependent):** Native controls are a good base, but repeated action labels lack row context; low-emphasis “missing” text is hard to perceive; and updates in the obscured workspace may not be announced where the interaction occurred.

**Riley (stress tester):** Long, duplicate, nonexistent, file-not-folder, and disappearing paths expose gaps in validation and layout. Draft input is cleared before async success, repeated actions stay enabled, and the additional-root backend currently checks existence rather than directory type.

## Minor Observations

- Use “Project folder,” “Detected agent folders,” “Additional folders,” and “GitHub access.”
- Prefer “Available / Not found” over lowercase “found / missing.”
- Capitalize provider display names while preserving literal filesystem paths.
- Show an explicit “Not set” project state rather than communicating it by absence.
- Use folder name as primary text and selectable, middle-truncated monospaced path as secondary text.
- Replace the redundant Appearance section/picker labels with one `LabeledContent` row.
- Keep System appearance as the default and explain that it follows macOS.

## Evidence Limits

The screenshot proves one dark-mode layout at one size. Keyboard traversal, VoiceOver output, Increase Contrast, localization, long-path layout, importer failures, and live appearance switching were not runtime-tested. Those remain validation items rather than confirmed behavior.

## Questions to Consider

1. Is Settings primarily a configuration surface or a filesystem diagnostic surface? The current screen tries to be both and lets diagnostics win.
2. If automatic agent folders require no decision, why are they the largest persistent object in the window?
3. What should the end-state reassurance be: active source count, successful rescan, or authenticated GitHub access?

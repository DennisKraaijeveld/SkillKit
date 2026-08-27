# Skillbook → SwiftUI migration

macOS-only native rewrite of the GPUI/Bezel shell. Domain logic stays in Rust (`skillbook-core`). The UI becomes a SwiftUI app that talks to a UniFFI `Session` object.

**Status (shipping):** SwiftUI is the app. `crates/skillbook` and Bezel/GPUI deps are gone. Remaining optional polish: About panel.

This document is the working plan. It is grounded in:

- The current GPUI app (`crates/skillbook/src/app.rs`, ~1,660 lines)
- `skillbook-core` (scan, lockfiles, GitHub, `npx skills`, watcher)
- [Agent Skills spec](https://agentskills.io/specification) (`SKILL.md` YAML + Markdown body)
- [`npx skills` CLI](https://www.skills.sh/docs/cli) and vercel-labs/skills update internals
- [UniFFI proc-macros](https://mozilla.github.io/uniffi-rs/latest/proc_macro/index.html) (records, enums with fields, objects)
- Apple: [`NavigationSplitView`](https://developer.apple.com/documentation/swiftui/navigationsplitview), [`Settings` scene](https://developer.apple.com/documentation/swiftui/settings), [`fileImporter`](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)), [`AttributedString` markdown](https://developer.apple.com/documentation/foundation/attributedstring/markdownparsingoptions/interpretedsyntax-swift.enum), menu `CommandGroup`

## Why this shape

SwiftUI is the right chrome for a short sidebar + settings + one document. GPUI/Bezel were paying for a game-engine renderer and a Notion-style block editor we do not need for `SKILL.md`.

We do **not** rewrite scan, lockfile matching, GitHub folder-hash checks, or `npx skills add --skill` in Swift. That code is already tested. UniFFI keeps it.

**Accepted losses**

| Drop | Why |
|---|---|
| Linux UI | SwiftUI is Apple-only. `skillbook-core` tests still run on Linux. |
| Bezel block editor | Replace with a monospace source editor + rendered preview. Frontmatter stays a separate YAML field (same split the GPUI app already uses because Bezel cannot round-trip YAML). |
| Bezel visual language | Use system sidebar, materials, badges, and Settings. Do not clone Bezel tokens. |
| GPUI crate | Remove `crates/skillbook` and Bezel workspace deps once the Swift app reaches parity. |

**Keep as-is**

- Config path: `~/Library/Application Support/Skillbook/config.toml`
- Global agent dirs, project scan root, custom folders
- npx lockfiles, scoped lookup, single-skill `add --skill`, update-all confirm
- Watch only skill folders; ignore `.git` / `Library` / caches

## Target product

- **macOS 15+** (Sequoia). The live Markdown editor uses TextKit 2 through SwiftMarkdownEngine while raw Markdown remains canonical on disk.
- **Xcode 16+**, Swift 6 language mode with complete strict-concurrency checking.
- Bundle id: `com.denniskraaijeveld.skillbook`
- Category: Developer Tools
- **No App Sandbox.** This is a developer utility that must read `~/.claude/skills`, `~/.cursor/skills`, spawn `npx` / `git`, and write `SKILL.md`. Sandbox would force security-scoped bookmarks for every agent dir and break `npx`. Hardened Runtime + notarization still apply at ship time.
- GitHub update checks are anonymous; Skillbook has no credential setting.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Skillbook.app (SwiftUI, macOS)             │
│  @Observable AppModel                       │
│  NavigationSplitView · Settings · commands  │
└──────────────────┬──────────────────────────┘
                   │ UniFFI  (blocking calls off MainActor)
┌──────────────────▼──────────────────────────┐
│  skillbook-ffi  (cdylib + staticlib)        │
│  Session: owns skills, config, watcher      │
│  DTOs only cross the FFI                    │
└──────────────────┬──────────────────────────┘
                   │ rustc
┌──────────────────▼──────────────────────────┐
│  skillbook-core  (unchanged public API)     │
│  40+ unit tests stay the source of truth    │
└─────────────────────────────────────────────┘
```

Swift never reconstructs `SkillSource`. The Rust `Session` holds the live `Vec<Skill>`. The UI sends **ids** (`canonical_dir` string) for save / update. That avoids PathBuf and lock-scope round-trips, which UniFFI does not express cleanly.

### Why UniFFI, not a Swift rewrite of core

- UniFFI 0.32 proc-macros: `Record`, `Enum` (including associated fields), `Object` + `#[uniffi::export]`.
- The Xcode pre-build script compiles the static library and regenerates the committed Swift/C bindings.
- Linux CI keeps running `cargo test -p skillbook-core` and `cargo test -p skillbook-ffi`.

### Why a `Session` object, not free functions

Free functions would require shipping the full skill graph through FFI on every keystroke. A UniFFI `Object` with an internal `Mutex<Inner>` matches how the GPUI `Workspace` already works: one owner, background work clones the vec, writes back.

## Current UI → SwiftUI map

Every surface in `Workspace` has a home.

| GPUI today | SwiftUI |
|---|---|
| Custom titlebar + search field | Default titlebar + `.searchable` on the split view |
| Status string in titlebar | Toolbar status `Text` (short: `12 skills`, `2 npx updates`) — keep it short; long copy caused layout jump in GPUI |
| Outdated / All toggle | Sidebar toolbar `Toggle` or menu |
| Refresh icon | `Button` + `Cmd+R` |
| Update all | Toolbar + `CommandGroup`; fetch then `.sheet` |
| Settings gear | Native **Settings** scene (`Cmd+,`) — not a detail replacement |
| Appearance sun/moon | Settings + `preferredColorScheme` |
| Split list \| detail | `NavigationSplitView` sidebar + detail. Column width via `.navigationSplitViewColumnWidth(min:ideal:max:)` (ideal ~280pt, matching `split: 0.28`) |
| Scope sections GLOBAL / PROJECT / CUSTOM | `List { Section("Global · \(n)") }` |
| Scope / project / collection / category hierarchy | `SidebarTree` projects canonical skills through every detected placement. Global-to-project symlinks share one skill identity but render in both locations |
| Use in Project | A focused sheet fuzzy-searches the immediate child folders of configured work folders, keeps Finder as a pinned fallback, then either creates conflict-safe symlinks in selected agent folders or installs an independent `skills.sh` copy |
| Duplicate checker | Groups separate canonical rows by upstream identity, or local name plus content hash. Linked placements remain one row and are never reported as duplicates |
| Row: name, description, status dot, npx, agents, bump, Update | `SkillRow` view. Update uses `.buttonStyle(.borderedProminent)` and must not steal list selection (`Button` in the row is fine in SwiftUI if it is a real `Button`, not an `onTapGesture` on the whole row) |
| Empty / skeleton | `ContentUnavailableView` + `redacted` while first scan |
| npx global banner | `safeAreaInset(edge: .top)` warning bar + Review |
| Read / Edit / Raw | `Picker` in the detail toolbar |
| Path + Save + Update | Detail `ToolbarItem`s. Save = `Cmd+S` via `CommandGroup(replacing: .saveItem)` |
| Markdown read + navigation | Read-only SwiftMarkdownEngine TextKit surface with a cursor-responsive heading rail |
| Raw mode | Incrementally highlighted TextKit source editor with native find and undo |
| Frontmatter disclosure + YAML field | Collapsed `DisclosureGroup("Skill settings")` + syntax-aware YAML source editor |
| Live Markdown editor | SwiftMarkdownEngine `NativeTextViewWrapper` bound directly to the Markdown `String`; TextKit 2 styles incrementally while preserving source |
| Update-all dialog | `.sheet` listing `name` + `from → to`, Cancel / Update |
| Error strip | `.alert` or banner under toolbar |
| Folder add as text field | **`fileImporter(allowedContentTypes: [.folder])`** plus optional path field. On macOS, prefer `.folder` over `.directory` so Open is enabled |
| Filesystem watcher | A blocking `waitForWatchChange()` call wakes Swift after Rust coalesces and debounces a relevant event |
| Ignore watcher after save/update | `session.ignoreWatch(ms:)` |

## Mandatory first-launch setup

The app root reads the persisted `onboarding_version` before starting its first scan. An incomplete installation sees a three-step prerequisite flow instead of `WorkspaceView`:

1. Welcome and explain the read-only filesystem check.
2. Detect supported agent harnesses from their known configuration, skills, and application locations.
3. Choose zero or more work folders and additional skill folders. If both lists are empty, the user must explicitly confirm that only detected agent folders should be used.

The setup uses official provider marks where available, brief blur-and-opacity transitions to soften step changes, and opacity-only alternatives when Reduce Motion is enabled.

There is no skip action. The normal workspace, skill commands, watcher, and editable Settings panes remain unavailable until Rust validates every chosen directory, atomically persists the complete configuration, and returns the initial scan. A malformed existing config is surfaced in the setup UI and blocks replacement instead of being silently overwritten.

macOS does not honor `NavigationSplitViewVisibility.detailOnly`. Do not build a “chrome-less editor” around that API. Sidebar hide is the user’s traffic-light / View menu behavior.

## Document model (`SKILL.md`)

Spec: YAML frontmatter (`name`, `description`, required) + Markdown body. Agentskills also allows `license`, `compatibility`, `metadata`, `allowed-tools`. The editor must **round-trip unknown YAML keys**. That is why we keep the raw YAML string, not a typed form.

Save path (unchanged):

```
join_skill_md(frontmatter, body) → write_skill_file(skill_md)
```

Dirty flag: composed text ≠ `savedCanonical`. Compute in Swift from the two strings; do not notify on every editor poll the way GPUI did.

Edit mode binds SwiftMarkdownEngine directly to the Markdown body string. Its TextKit 2 renderer incrementally styles headings, emphasis, lists, task items, links, code blocks, and GFM tables without converting the file into a lossy rich-text persistence format.

Read mode uses the same native TextKit surface with editing disabled, so scrolling and layout do not switch implementations. `swift-markdown` parses headings off the main actor for the compact section rail, source-range jumps, and hover previews.

## FFI surface (`crates/skillbook-ffi`)

Namespace `skillbook`. Library `libskillbook_ffi`.

```text
Session
  new() -> Session
  scan(silent: Bool) -> Snapshot
  checkUpdates() -> Snapshot
  readSkill(id) -> ParsedSkill
  saveSkill(id, yaml, body)
  updateSkill(id) -> UpdateOutcome
  previewUpdates() -> Snapshot     // check + return versionChanges
  applyUpdates(ids) -> [UpdateOutcome]
  waitForWatchChange() -> Bool
  interruptWatchWait()
  ignoreWatch(ms: UInt32)
  config() -> ConfigView
  detectHarnesses() -> [AgentHarness]
  completeOnboarding(projectRoots[], customRoots[]) -> Snapshot
  addProjectRoot(path)
  removeProjectRoot(path)
  linkSkill(id, projectRoot, agents[])
  installSkillInProject(spec, skill?, projectRoot)
  addCustomRoot(path)
  removeCustomRoot(path)
  setAppearance(mode)             // system | light | dark
```

DTOs (UniFFI records / enums), all paths as `String`:

- `FfiSkillRow`: canonical id, source collection/category metadata, and every placement (`agent`, `scope`, root, path, symlink state), plus version/update fields
- `FfiSnapshot`: skills, errors, statusHint, npxBanner, versionChanges, scanning
- `FfiParsedSkill`: yaml, body, name, description
- `FfiVersionChange`, `FfiUpdateOutcome`, `FfiConfig`
- `FfiAgentHarness`: harness id, detection state, and its known skill directories with existence and skill counts
- `SkillbookError::Message`

`checkUpdates` / `update*` / `scan` clone under the mutex, run **without** holding the lock, then write back. Same race the GPUI app already has (scan during check). A monotonic `generation` can be added later if it bites.

Swift calling convention:

```swift
Task.detached {
    let snap = try session.scan(silent: false)
    await MainActor.run { model.apply(snap) }
}
```

Never call blocking UniFFI from `@MainActor` without `Task.detached`. `npx` and `git pull` can take seconds.

## App structure (Swift)

```
macos/
  project.yml                 # XcodeGen
  Skillbook/
    SkillbookApp.swift        # WindowGroup + Settings + commands
    AppModel.swift            # @Observable, owns Session
    Views/
      WorkspaceView.swift     # NavigationSplitView
      SidebarView.swift
      SkillRowView.swift
      DetailView.swift
      MarkdownPreview.swift
      EditorPane.swift
      NpxBanner.swift
      UpdateSheet.swift
    Settings/
      SettingsView.swift      # Form tabs: Folders, Updates, Appearance
    Skillbook.entitlements    # no sandbox
```

`AppModel` holds: session, snapshot, selection id, query, outdatedOnly, viewMode, previewSub, yaml, body, savedCanonical, dirty, banner, sheet changes, error.

Selection change → `readSkill` on a background task → set yaml/body on MainActor if `selectedId` still matches (avoid stale loads).

## Settings

Use a `Settings` scene, not an in-window page. That is what macOS users expect for `Cmd+,`.

- Sources: project folder (Choose… via `fileImporter` `.folder`), additional folders, and detected agent folders
- Appearance: System / Light / Dark → `setAppearance` + `preferredColorScheme` on both app scenes

`fileImporter` completion: `startAccessingSecurityScopedResource()` is a no-op without sandbox; still call it so enabling sandbox later does not break.

## Commands and shortcuts

| Shortcut | Action |
|---|---|
| ⌘1 / ⌘2 / ⌘3 | Edit / Read / Raw |
| ⌥⌘F | Focus skill search |
| ⌘S | Save selected |
| ⌘F | Find in the active document (system) |
| ⌘R | Rescan |
| ⌘, | Settings (system) |
| ⌘Q | Quit (system) |
| ⌘⇧U | Update all (fetch then sheet) |

All app-defined shortcuts are editable in **Settings → Shortcuts**. Overrides are stored in user defaults, reject duplicate assignments, and update menu and toolbar key equivalents immediately.

```swift
.commands {
    CommandGroup(replacing: .saveItem) { Button("Save") { model.save() }.keyboardShortcut("s") }
    CommandGroup(after: .sidebar) { Button("Reload Skills") { model.rescan() }.keyboardShortcut("r") }
}
```

## Watcher

Keep Rust `notify` + `path_is_relevant` + 600ms debounce. Swift blocks off the main actor until Rust reports a coalesced change:

```swift
.task {
    while !Task.isCancelled {
        if await backend.waitForWatchChange() {
            await model.rescan(silent: true)
        }
    }
}
```

Cancellation calls `interruptWatchWait()` so the detached blocking wait does not outlive its view task.

Silent rescan must call `preserve_version_state` in Rust (already in core) so badges do not flash.

After save: `ignoreWatch(ms: 800)`. After npx/git: `2000`.

## npx / git updates

No change to argv construction. Swift shows UI only:

- Row Update visible iff `version == updateAvailable`
- Fetch-all: `previewUpdates()` then sheet; confirm → `applyUpdates(ids)`
- Banner text from `global_package_banner` (already in core)

## Build & packaging

1. XcodeGen: `cd macos && xcodegen`
2. `scripts/build-ffi.sh` installs/builds every Darwin target in Xcode's `ARCHS` value.
3. The script regenerates the UniFFI Swift/C output and combines arm64/x86_64 release archives with `lipo`.
4. Xcode links the generated static archive into the app.
5. Sign, notarize, and staple when shipping.

Dev loop on a Mac: the Run Script build phase compiles the active Debug architecture and every requested Release architecture, then synchronizes generated Swift into the target. Do not check in `.a` binaries.

Linux/CI: `cargo test -p skillbook-core -p skillbook-ffi` only. No SwiftUI job until we have a Mac runner.

## Phases

### 0 — Plan (this doc)

Done when the team agrees: Session-in-Rust, no sandbox, no block editor, Settings scene.

### 1 — FFI crate (Linux-friendly)

- `crates/skillbook-ffi` wrapping core
- Snapshot / Session tests using tempdirs (reuse core scan fixtures conceptually)
- GPUI app **untouched** and still runnable

### 2 — Empty SwiftUI shell

- XcodeGen project, entitlements, WindowGroup, Settings stub
- NavigationSplitView with placeholder sidebar/detail
- Commands wired to no-ops

### 3 — Read-only manager

- Link FFI
- Scan on launch, sectioned list, search, outdated filter
- Select → preview (AttributedString + outline + badges)
- Status string + npx banner (Review can no-op until phase 5)

### 4 — Edit / save

- Frontmatter disclosure + body `TextEditor`
- Dirty, Save, Cmd+S
- Watcher ignore after write
- Guard: do not reload selection over unsaved dirty buffer (GPUI currently reloads on select; keep a “discard?” alert)

### 5 — Versions and updates

- Background `checkUpdates` after non-silent scan
- Row + toolbar Update
- Update-all fetch → sheet → apply
- Watcher + silent rescan preserving versions

### 6 — Settings parity

- Scan root / custom folders via folder picker
- Appearance
- Persist toml through Session

### 7 — Polish

- ContentUnavailableView empty states
- Progress for first scan
- About panel, sparkle-free
- README: `cd macos && xcodegen && open Skillbook.xcodeproj`

### 8 — Delete GPUI

Done. `crates/skillbook` and Bezel/gpui workspace deps are removed. Workspace members are `skillbook-core` + `skillbook-ffi`.

## Testing

| Layer | How |
|---|---|
| Domain | Existing `cargo test -p skillbook-core` |
| FFI mapping | `cargo test -p skillbook-ffi`: scan temp home, config roundtrip, preserve versions on silent scan |
| Swift model/backend | Swift Testing target with `AppModel` validation and `PreviewBackend` lifecycle coverage |
| Swift UI | XCTest/XCUIAutomation for critical end-to-end flows |
| Manual (Mac) | Global npx skill with lockfile; project skill same name; save frontmatter; update one; update all confirm; FS event debounce |

## Risks

| Risk | Mitigation |
|---|---|
| App Sandbox enabled by Xcode template | Entitlements file with sandbox off; verify with `codesign -d --entitlements` |
| Blocking FFI on main thread | `Task.detached` convention in AppModel only |
| UniFFI + PathBuf | Never export `PathBuf`; Session holds real skills |
| Markdown tables look wrong | Preview is informational; Source tab shows truth |
| `npx` not on GUI app PATH | Session prepends `/usr/local/bin:/opt/homebrew/bin` to `PATH` when spawning (do this in ffi when calling update) |
| Stale `readSkill` after fast selection | Compare id before applying parsed file |
| Layout jump from status text | Toolbar status stays a short phrase; banner is below the bar |
| Shipping universal binary | `build-ffi.sh` builds and combines the arm64 and x86_64 archives requested by Xcode |

## What “done” means

Parity with the current GPUI app for: discover, filter, preview, edit+save without flattening YAML, version check, single update, update-all confirm, npx badge + global pack banner, settings folders/appearance, filesystem watch without watching `$HOME`.

Not in v1: Bezel block editor, Linux GUI, skill validation against skills-ref, iCloud.

## Implementation note

`crates/skillbook-ffi` and `macos/Skillbook` are the shipping stack. On a Mac: `cd macos && xcodegen && open Skillbook.xcodeproj`. Linux/CI runs `cargo test -p skillbook-core -p skillbook-ffi`.

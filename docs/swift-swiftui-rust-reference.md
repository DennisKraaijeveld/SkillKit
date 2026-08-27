# Swift, SwiftUI, and Rust documentation hub

Last source review: **2026-08-26**

This is a curated map of the current primary documentation, not a vendored copy of the upstream docsets. Apple, Swift, and Rust update their references continuously; linking to the owners keeps API availability, corrections, and release notes current. The version snapshot below makes the word “current” auditable.

## Version snapshot and ground rules

| Area | Current status on 2026-08-26 | What to pin in a project |
|---|---|---|
| Swift language | **Swift 6.3.3** is the latest stable Swift toolchain. Swift 6.3 was released on 2026-03-24 and the stable patch tag is `swift-6.3.3-RELEASE`. The online language book already identifies itself as **6.4 beta**, so it can describe features that are not in the stable toolchain. ([Swift 6.3 release](https://www.swift.org/blog/swift-6.3-released/), [6.3.3 source tag](https://github.com/swiftlang/swift/tree/swift-6.3.3-RELEASE), [language book](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/)) | Pin the Xcode/Swift toolchain in CI and declare the package tools version. Check the compiler actually selected with `xcrun swift --version` or `swift --version`. ([SwiftPM tools version](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/settingswifttoolsversion/), [Swift install guide](https://www.swift.org/install/)) |
| Swift language mode | Swift compiler version and Swift language mode are different controls. Swift 6 mode enables complete data-race safety checking, and migration can happen one target at a time. ([version compatibility](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/compatibility/), [Swift 6 migration guide](https://www.swift.org/migration/)) | Record the intended language mode per target; do not infer it only from the installed compiler. |
| SwiftUI | SwiftUI has no independent semantic version. Its APIs ship in Apple SDKs, and every symbol carries per-platform availability. ([SwiftUI reference](https://developer.apple.com/documentation/swiftui/), [checking API availability](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/attributes/#Declaration-Attributes)) | Pin Xcode and deployment targets; gate newer APIs with availability declarations/checks or an older implementation. |
| Rust | **Rust 1.98.0** is the current stable release (2026-08-20). The Rust project only provides fixes and security updates for its latest stable version. ([latest release](https://blog.rust-lang.org/releases/latest/), [Cargo MSRV guidance](https://doc.rust-lang.org/stable/cargo/reference/rust-version.html)) | A `stable` rustup channel floats. Pin an exact toolchain when reproducibility matters, and declare `package.rust-version` when publishing/supporting an MSRV. ([toolchain overrides](https://rust-lang.github.io/rustup/overrides.html), [Cargo `rust-version`](https://doc.rust-lang.org/stable/cargo/reference/rust-version.html)) |
| Rust edition | **Edition 2024** is the current stable edition. Editions are opt-in per crate and preserve cross-edition interoperability. ([Edition Guide](https://doc.rust-lang.org/stable/edition-guide/), [Rust 2024 release](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/)) | Set `edition = "2024"` per package. In a virtual workspace, set the resolver explicitly; edition 2024’s default resolver is version 3. ([Cargo resolver](https://doc.rust-lang.org/stable/cargo/reference/resolver.html#resolver-versions), [virtual workspaces](https://doc.rust-lang.org/stable/cargo/reference/workspaces.html#virtual-workspace)) |

### Verified local baseline

The following was verified in this checkout on 2026-08-26:

| Layer | Effective/local value | Important distinction |
|---|---|---|
| Xcode and compiler | **Xcode 26.6** (build `17F113`) selects **Apple Swift 6.3.3** (`swiftlang-6.3.3.1.3`). | This is the compiler toolchain, not automatically the source language mode. Apple documents the current Xcode/SDK matrix separately in [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/). |
| Skillbook Swift build configuration | [`macos/project.yml`](../macos/project.yml) sets `SWIFT_VERSION: "6.0"`, complete strict-concurrency checking, and macOS deployment target **15.0**; the generated Xcode project contains the same values. | The app uses Swift 6 language mode and can use macOS 15 SwiftUI APIs directly. Newer SDK APIs still require availability handling. ([version compatibility](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/compatibility/), [Swift 6 migration](https://www.swift.org/migration/)) |
| Rust compiler and Cargo | **rustc 1.98.0** (`88d9e12ae`, 2026-08-18) and **Cargo 1.98.0**. | [`rust-toolchain.toml`](../rust-toolchain.toml) pins `1.98.0`, and the workspace packages declare `rust-version = "1.98"`. Update these deliberately together. ([toolchain files](https://rust-lang.github.io/rustup/overrides.html#the-toolchain-file), [Cargo `rust-version`](https://doc.rust-lang.org/stable/cargo/reference/rust-version.html)) |
| Skillbook Rust source configuration | [`Cargo.toml`](../Cargo.toml) sets workspace edition **2024** and resolver **3**. | Resolver 3 is explicit because this is a virtual workspace, and it honors Rust-version-aware dependency fallback by default. ([Cargo resolver versions](https://doc.rust-lang.org/stable/cargo/reference/resolver.html#resolver-versions), [virtual workspaces](https://doc.rust-lang.org/stable/cargo/reference/workspaces.html#virtual-workspace)) |

## Shortest useful learning paths

### New to Swift and SwiftUI

1. Work through [A Swift Tour](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/guidedtour/) and use [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/) as the language reference.
2. Follow Apple’s [SwiftUI Pathway](https://developer.apple.com/swiftui/get-started/) and [Develop in Swift tutorials](https://developer.apple.com/tutorials/develop-in-swift/).
3. Learn the modern data model through [Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app/) and navigation through [Understanding the navigation stack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack).
4. Before shipping, use Apple’s [testing](https://developer.apple.com/documentation/xcode/testing), [accessibility](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals), and [SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) guidance.

### New to Rust

1. Work through [The Rust Programming Language](https://doc.rust-lang.org/stable/book/) and keep [Rust by Example](https://doc.rust-lang.org/rust-by-example/) nearby.
2. Use the [standard library reference](https://doc.rust-lang.org/stable/std/) for APIs and the [Rust Reference](https://doc.rust-lang.org/stable/reference/) for language rules.
3. Read the [Cargo Book](https://doc.rust-lang.org/stable/cargo/) for builds, packages, dependencies, features, profiles, and publishing.
4. Add [rustfmt](https://github.com/rust-lang/rustfmt), [Clippy](https://doc.rust-lang.org/stable/clippy/), tests, and rustdoc to the normal feedback loop; go to [The Rustonomicon](https://doc.rust-lang.org/stable/nomicon/) before writing unsafe Rust.

## Swift language reference

### Canonical documentation

| Need | Primary source | Use it for |
|---|---|---|
| Documentation landing page | [Swift.org Documentation](https://www.swift.org/documentation/) | The maintained directory for the language, packages, tooling, DocC, interoperability, server, embedded, and platform guides. |
| Language guide and grammar | [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/) | Syntax, types, ownership, ARC, memory safety, generics, protocols, concurrency, and the formal grammar. The live page may track a beta toolchain, so check its displayed version. |
| Standard library API | [Swift standard library](https://developer.apple.com/documentation/swift) | Types and protocols shipped in the `Swift` module, including collections, optionals, results, tasks, actors, and `Sendable`. |
| Accepted and proposed language changes | [Swift Evolution](https://www.swift.org/swift-evolution/) and [proposal repository](https://github.com/swiftlang/swift-evolution) | Proposal status and the release in which an accepted change is implemented. Accepted does not by itself mean available in the selected stable compiler. |
| Compatibility | [Version Compatibility](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/compatibility/) | Compiler versus language mode, runtime/OS availability, and incremental module migration. |
| Releases | [Swift blog](https://www.swift.org/blog/) and [Swift releases](https://www.swift.org/install/) | Stable release announcements, downloads, installation, and platform instructions. |
| Diagnostics | [Swift compiler diagnostics](https://docs.swift.org/compiler/documentation/diagnostics/) | Explanations and fixes for compiler diagnostic groups. |

### Core topics

- Values, control flow, functions, closures, enums, structs/classes, properties, protocols, generics, opaque types, and access control are all indexed by the [language guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/).
- Prefer value semantics when they model the domain; understand identity, shared mutation, and ARC before choosing a class. The language book distinguishes structure/enumeration value semantics from class reference semantics and documents ARC lifetime behavior. ([structures and classes](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/classesandstructures/), [automatic reference counting](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/))
- Model expected absence with `Optional`, recoverable failure with throwing functions or `Result` where a stored value is needed, and reserve traps/preconditions for violated programmer invariants. ([error handling](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/), [`Result`](https://developer.apple.com/documentation/swift/result))
- Public APIs should optimize clarity at the call site, follow established naming conventions, and include documentation comments. ([Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/))
- Use explicit access control to keep implementation details out of a module’s API; library authors should review resilience and ABI guidance before promising binary compatibility. ([access control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/), [library evolution](https://www.swift.org/blog/library-evolution/))

### Concurrency and safety

- Start with the language book’s [Concurrency chapter](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) and the standard library’s [Concurrency index](https://developer.apple.com/documentation/swift/concurrency). Swift’s structured child tasks do not outlive their parent scope, which makes lifetime and cancellation easier to reason about. ([`TaskGroup`](https://developer.apple.com/documentation/swift/taskgroup))
- Put UI-isolated state and work on `MainActor`; move long-running or CPU-intensive work away from it without assuming that an actor is identical to a thread. ([Concurrency: The Main Actor](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#The-Main-Actor))
- Use actors to serialize mutable shared state and `Sendable` to express values that can cross isolation domains. Treat `@unchecked Sendable` as a manual safety proof, not a compiler workaround. ([actors and sendable types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Actors), [`Sendable`](https://developer.apple.com/documentation/swift/sendable))
- Prefer structured tasks and task groups when work has a lexical owner. Use unstructured or detached tasks only when their independent lifetime and isolation are deliberate, and retain a cancellation strategy. ([tasks and task groups](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Tasks-and-Task-Groups), [task cancellation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Task-Cancellation))
- Adopt Swift 6 data-race checking incrementally per target rather than suppressing warnings wholesale. The official migration strategy recommends enabling stricter checks while still in Swift 5 mode, addressing warnings, and then enabling Swift 6 mode. ([migration strategy](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/migrationstrategy/), [incremental adoption](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption/))
- For security-critical code, Swift’s opt-in strict memory-safety mode diagnoses uses of unsafe constructs and APIs so each can be removed or explicitly acknowledged. ([strict memory-safety diagnostic](https://docs.swift.org/compiler/documentation/diagnostics/strict-memory-safety/), [SwiftPM setting](https://docs.swift.org/swiftpm/documentation/packagedescription/swiftsetting/strictmemorysafety%28_%3A%29/))
- Review pointer lifetime, binding, alignment, exclusivity, and C/C++ contracts at every unsafe boundary. The compiler cannot prove the external invariant that makes an unsafe operation sound. ([memory safety](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/memorysafety/), [manual memory management](https://developer.apple.com/documentation/swift/manual-memory-management))

### Packages, builds, tools, and documentation

| Area | Primary docs | Practical rule |
|---|---|---|
| Swift Package Manager | [SwiftPM documentation](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/) and [`PackageDescription`](https://docs.swift.org/swiftpm/documentation/packagedescription/) | Declare the minimum tools version and explicit target/product/dependency boundaries; keep the resolved dependency state under the project’s chosen policy. |
| Package security | [SwiftPM package security](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/packagesecurity) | Review dependency identity, signatures/checksums, registry trust, and credentials instead of treating resolution as a security review. |
| CLI | [`swift build`](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/swiftbuild/), [`swift test`](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/swifttest/), and [`swift package`](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/swiftpackagecommands/) | Use the same pinned toolchain and materially equivalent build/test flags locally and in CI. |
| Debugging | [LLDB](https://www.swift.org/lldb/) | Use LLDB through Xcode or the command line for source debugging and the REPL. |
| Editor support | [SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) | Prefer the official language-server integration for non-Xcode editors. |
| API documentation | [DocC](https://www.swift.org/documentation/docc/) | Keep symbol comments and conceptual articles beside the code; build DocC to validate links and publish an archive. |

### Testing

- Use [Swift Testing](https://developer.apple.com/documentation/testing) for new unit and integration tests. It supports async tests, parameterization, tags, traits, and parallel execution. ([Swift Testing overview](https://developer.apple.com/xcode/swift-testing/))
- Continue to use [XCTest](https://developer.apple.com/documentation/xctest) with XCUIAutomation for UI tests and XCTest performance APIs for performance regression tests; Apple explicitly recommends this division while Swift Testing and XCTest coexist. ([Xcode testing guidance](https://developer.apple.com/documentation/xcode/testing))
- Maintain many fast isolated unit tests, fewer integration tests, and a focused set of critical user-flow UI tests; add performance tests around performance-critical regions. This is Apple’s documented testing-pyramid guidance. ([Testing](https://developer.apple.com/documentation/xcode/testing))
- Test positive, negative, boundary, cancellation, and error paths. For UI tests, exercise supported devices, window sizes, appearances, locales, and accessibility settings. ([testing and performance](https://developer.apple.com/documentation/technologyoverviews/testing-and-performance))
- Use test plans to separate fast feedback from full, multi-configuration validation, and run them in CI. ([organizing tests into test plans](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback))
- Use Address Sanitizer and Thread Sanitizer in suitable test jobs; sanitizers slow execution and are diagnostic builds, not production configurations. ([Swift server testing guide](https://www.swift.org/documentation/server/guides/testing.html), [Xcode diagnostics](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early))

## SwiftUI reference

### Canonical indexes

| Need | Primary source |
|---|---|
| Complete framework symbol/topic index | [SwiftUI framework reference](https://developer.apple.com/documentation/swiftui/) |
| Curated learning sequence | [SwiftUI Pathway](https://developer.apple.com/swiftui/get-started/) |
| Release-by-release API additions | [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui) |
| Platform design conventions | [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) |
| Sample projects | [Apple SwiftUI sample code](https://developer.apple.com/documentation/swiftui#Featured-samples) |

### App and scene structure

- Declare the entry point with `App`, then compose scenes such as `WindowGroup`, `Settings`, or `DocumentGroup` according to the product’s window/document model. Keep launch initialization small and defer noncritical work until the UI is present. ([SwiftUI apps overview](https://developer.apple.com/documentation/technologyoverviews/swiftui))
- Use the [App organization](https://developer.apple.com/documentation/swiftui/app-organization), [Scenes](https://developer.apple.com/documentation/swiftui/scenes), [Windows](https://developer.apple.com/documentation/swiftui/windows), and [Documents](https://developer.apple.com/documentation/swiftui/documents) topic indexes rather than inventing a custom lifecycle around view callbacks.
- A `View` declaration is a lightweight description, not a persistent view-controller instance. Persistent domain state belongs in an explicit source of truth, not in assumptions about a view struct’s lifetime. ([SwiftUI apps overview](https://developer.apple.com/documentation/technologyoverviews/swiftui), [model data](https://developer.apple.com/documentation/swiftui/model-data))

### State and data flow

- Keep transient view-owned value state private in `@State`; pass writable access to an owner’s state with `@Binding`. Use the smallest owner and dependency surface that describes the real source of truth. ([model data](https://developer.apple.com/documentation/swiftui/model-data), [managing UI state](https://developer.apple.com/documentation/swiftui/managing-user-interface-state))
- On iOS 17, iPadOS 17, macOS 14, tvOS 17, and watchOS 10 or later, use Observation’s `@Observable` for observable models, store a view-owned instance in `@State`, use `@Bindable` when a control needs bindings to its properties, and inject broadly shared models through the environment when appropriate. ([managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app/))
- For earlier deployment targets, use the documented `ObservableObject`, `@StateObject`, `@ObservedObject`, and `@EnvironmentObject` model. Do not mix the two models accidentally; follow Apple’s [Observation migration guide](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro).
- Treat derived display values as derived values instead of duplicated mutable state. SwiftUI updates views from their declared state, environment, and observable dependencies; a smaller dependency graph also makes unexpected updates easier to diagnose. ([model data](https://developer.apple.com/documentation/swiftui/model-data), [SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance))
- Bind asynchronous work to a view’s lifetime with the [`task` modifier family](https://developer.apple.com/documentation/swiftui/view/task%28id%3Aname%3Apriority%3Afile%3Aline%3A_%3A%29) when that is the actual lifetime; SwiftUI can cancel the task when the view disappears and cancels/restarts the identified form when its identity changes.

### Navigation and presentation

- Use `NavigationStack` for stack navigation and `NavigationSplitView` for multicolumn interfaces. Prefer value-based destinations and keep navigation-path values lightweight; Apple specifically cautions against using model objects as path transport. ([navigation](https://developer.apple.com/documentation/swiftui/navigation), [understanding the navigation stack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack), [robust navigation sample](https://developer.apple.com/documentation/swiftui/bringing-robust-navigation-structure-to-your-swiftui-app))
- Model programmatic navigation as data so deep links and state restoration can rebuild it. Use `NavigationPath` only when a heterogeneous path is needed; use a typed array for a homogeneous path. ([understanding the navigation stack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack))
- Model sheets, alerts, confirmation dialogs, and popovers from a single authoritative optional item or Boolean. Ensure dismissal/cancellation returns model state to the same truth. Start from the [modal presentations](https://developer.apple.com/documentation/swiftui/modal-presentations) topic index.

### Layout, collections, and identity

- Start with stacks, grids, lists, forms, and platform containers. Use a custom `Layout` only when built-in containers cannot express the needed geometry. ([layout fundamentals](https://developer.apple.com/documentation/swiftui/layout-fundamentals), [`Layout`](https://developer.apple.com/documentation/swiftui/layout))
- Start with eager `HStack`/`VStack`; switch to lazy stacks/grids when measurement shows a worthwhile benefit. Lazy containers create children on demand but trade some layout predictability for that behavior. ([picking container views](https://developer.apple.com/documentation/swiftui/picking-container-views-for-your-content), [performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks))
- Give collection elements stable semantic identity. Changing or deriving unstable IDs can destroy row state, break animations, and cause unnecessary work because SwiftUI uses identity to track view lifetime. ([Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/), [`ForEach`](https://developer.apple.com/documentation/swiftui/foreach))
- Prefer adaptive layout and system spacing over fixed screen assumptions. Test resizable macOS windows, Dynamic Type, right-to-left layout, long localized strings, and accessibility sizes. ([layout fundamentals](https://developer.apple.com/documentation/swiftui/layout-fundamentals), [HIG layout](https://developer.apple.com/design/human-interface-guidelines/layout))

### Controls, input, and platform behavior

- Use semantic controls such as `Button`, `Toggle`, `Picker`, `TextField`, `List`, `Table`, and `Form` instead of recreating interaction with a tap gesture; standard controls supply platform behavior, focus, keyboard, and baseline accessibility. ([controls and indicators](https://developer.apple.com/documentation/swiftui/controls-and-indicators), [accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals))
- Add keyboard commands and focus state where the platform expects them, and keep labels/actions meaningful without pointer input. ([input events](https://developer.apple.com/documentation/swiftui/input-events), [focus](https://developer.apple.com/documentation/swiftui/focus))
- Bridge an AppKit/UIKit control only for behavior SwiftUI does not provide, and keep the representable’s update and coordinator responsibilities narrow. ([AppKit integration](https://developer.apple.com/documentation/swiftui/appkit-integration), [UIKit integration](https://developer.apple.com/documentation/swiftui/uikit-integration))

### Accessibility and localization

- SwiftUI gives standard controls baseline accessibility, but custom content still needs accurate labels, values, traits, actions, grouping, focus order, and navigation. Validate with VoiceOver, Voice Control, Switch Control, keyboard-only use, and Accessibility Inspector. ([accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals), [creating accessible views](https://developer.apple.com/documentation/swiftui/creating-accessible-views), [Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector))
- Do not encode meaning in color alone; support increased contrast, reduced motion/transparency, large text, and system semantic colors/materials. ([accessible appearance](https://developer.apple.com/documentation/swiftui/accessible-appearance), [HIG accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility))
- Localize user-visible text and formatting, then test expansion, pluralization, grammatical variation, and right-to-left layout. Prefer locale-aware Foundation formatters and SwiftUI localization facilities. ([localization](https://developer.apple.com/documentation/xcode/localization), [localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog))

### Performance and diagnostics

- Keep `body` calculations quick, deterministic, and free of blocking I/O. Long or frequent view updates can miss display frames; use Instruments’ SwiftUI template to identify the actual long body/platform updates and update groups. ([understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance))
- Profile before replacing containers, caching derived values, adding manual equality, or restructuring observation. Instruments covers hangs, hitches, CPU, memory, SwiftUI updates, and concurrency. ([performance analysis](https://developer.apple.com/documentation/swiftui/performance-analysis), [testing and performance](https://developer.apple.com/documentation/technologyoverviews/testing-and-performance))
- Avoid broad observable dependencies and unnecessary identity changes; both can increase the frequency of work. Confirm suspected redraws with the SwiftUI instrument rather than treating `body` evaluation as proof of rendered work. ([SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance))
- Use [Xcode previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) for fast state/configuration inspection, but keep unit, UI, accessibility, and performance tests as the verification layer.

## Rust language and ecosystem reference

### Canonical documentation

| Need | Primary source | Notes |
|---|---|---|
| Learn the language | [The Rust Programming Language](https://doc.rust-lang.org/stable/book/) | Ownership/borrowing, enums/patterns, errors, traits/generics/lifetimes, tests, smart pointers, concurrency, async, and unsafe Rust. |
| Learn by runnable examples | [Rust by Example](https://doc.rust-lang.org/rust-by-example/) | Topic-organized examples that can be executed in the browser. |
| Exact language rules | [Rust Reference](https://doc.rust-lang.org/stable/reference/) | Syntax and semantics. Use it instead of inferring a rule from compiler behavior. |
| Library APIs | [standard library](https://doc.rust-lang.org/stable/std/) | `core`, `alloc`, and `std` APIs with source links and stability markers. |
| Editions and migrations | [Edition Guide](https://doc.rust-lang.org/stable/edition-guide/) | Edition changes and `cargo fix --edition` migration guidance. |
| Unsafe Rust | [The Rustonomicon](https://doc.rust-lang.org/stable/nomicon/) and [Reference: unsafety](https://doc.rust-lang.org/stable/reference/unsafety.html) | Unsafe invariants, FFI, layout, aliasing, variance, ownership edge cases, and the normative unsafe operations list. |
| Compiler | [rustc book](https://doc.rust-lang.org/stable/rustc/) and [error index](https://doc.rust-lang.org/stable/error_codes/error-index.html) | Compiler flags, targets, lints, codegen, diagnostics, tests, and platform behavior. |
| Build/package manager | [Cargo Book](https://doc.rust-lang.org/stable/cargo/) | Manifests, workspaces, resolution, features, build scripts, profiles, commands, registries, and publishing. |
| API documentation | [rustdoc book](https://doc.rust-lang.org/stable/rustdoc/) | Documentation comments, doctests, intra-doc links, attributes, JSON, and linting. |
| Release state | [latest stable release](https://blog.rust-lang.org/releases/latest/) and [detailed release notes](https://doc.rust-lang.org/stable/releases.html) | Stable release date and compiler/library/tool changes. |
| Platform tiers | [platform support](https://doc.rust-lang.org/stable/rustc/platform-support.html) | Target tiers and guarantees; a target’s presence does not imply every external linker/system dependency is bundled. |

### Ownership, errors, and API design

- Treat ownership and borrowing as the design model, not an obstacle to bypass with cloning, reference counting, or interior mutability. Start with [ownership](https://doc.rust-lang.org/stable/book/ch04-00-understanding-ownership.html), then [smart pointers](https://doc.rust-lang.org/stable/book/ch15-00-smart-pointers.html), and introduce shared ownership only where the domain actually has shared ownership.
- Represent closed alternatives and state transitions with enums and exhaustive `match`; use the type system to make invalid states difficult to construct. ([enums and pattern matching](https://doc.rust-lang.org/stable/book/ch06-00-enums.html), [patterns](https://doc.rust-lang.org/stable/book/ch19-00-patterns.html))
- Return `Result` for recoverable errors and reserve panics for unrecoverable states or violated invariants. Propagate while retaining actionable context at the layer that can add it. ([error handling](https://doc.rust-lang.org/stable/book/ch09-00-error-handling.html), [`Result`](https://doc.rust-lang.org/stable/std/result/))
- Design public crates using the [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) and Cargo’s [SemVer compatibility guide](https://doc.rust-lang.org/stable/cargo/reference/semver.html). Public type layout, trait implementations, feature behavior, and MSRV changes can all affect compatibility.
- Declare an MSRV with `package.rust-version`, publish its policy, and test it if it is a support promise. Cargo can use the field for diagnostics and dependency resolution. ([Cargo Rust version](https://doc.rust-lang.org/stable/cargo/reference/rust-version.html))

### Concurrency and async

- Rust’s ownership/type system makes many concurrency bugs compile-time errors; `Send` marks values transferable across threads and `Sync` marks types safe to reference from multiple threads. ([fearless concurrency](https://doc.rust-lang.org/stable/book/ch16-00-concurrency.html), [`Send` and `Sync`](https://doc.rust-lang.org/stable/nomicon/send-and-sync.html))
- Prefer message passing or clearly owned synchronization over unstructured shared mutable state. Choose `Mutex`, `RwLock`, atomics, or channels based on the data invariant and contention model, and handle poisoning/shutdown explicitly. ([shared-state concurrency](https://doc.rust-lang.org/stable/book/ch16-03-shared-state.html), [`std::sync`](https://doc.rust-lang.org/stable/std/sync/))
- Learn language-level futures, `async`/`await`, tasks, streams, and pinning in the current [async chapter of The Book](https://doc.rust-lang.org/stable/book/ch17-00-async-await.html). Runtime, timer, I/O, and executor behavior comes from the chosen runtime’s own primary documentation, not from the Rust language itself.
- Never block an async executor thread with long synchronous I/O or CPU work unless the runtime explicitly provides and you use its blocking-work mechanism. The language’s `Future` is inert until polled by an executor. ([`Future`](https://doc.rust-lang.org/stable/std/future/trait.Future.html), [async fundamentals](https://doc.rust-lang.org/stable/book/ch17-01-futures-and-syntax.html))

### Unsafe Rust, FFI, and memory safety

- Keep unsafe regions small and expose a safe abstraction only after stating and upholding every invariant. `unsafe` transfers a proof obligation to the programmer; it does not disable the borrow checker or make an operation sound. ([Reference: `unsafe`](https://doc.rust-lang.org/stable/reference/unsafe-keyword.html), [Unsafe Rust](https://doc.rust-lang.org/stable/book/ch20-01-unsafe-rust.html))
- Document the safety conditions of every `unsafe fn`, `unsafe trait`, and unsafe implementation. Edition 2024 warns on unsafe operations inside an `unsafe fn` unless they are in an explicit unsafe block, which separates the caller’s obligations from the implementation’s proof. ([unsafe keyword](https://doc.rust-lang.org/stable/reference/unsafe-keyword.html), [edition-2024 unsafe operations](https://doc.rust-lang.org/stable/edition-guide/rust-2024/unsafe-op-in-unsafe-fn.html))
- For FFI, specify ABI, ownership transfer, allocation/deallocation pairing, pointer validity/alignment, nullability, lifetimes, unwinding behavior, threading, and callback lifetime on both sides. ([Rustonomicon FFI](https://doc.rust-lang.org/stable/nomicon/ffi.html), [Reference external blocks](https://doc.rust-lang.org/stable/reference/items/external-blocks.html))
- Use Miri on unsafe-heavy pure-Rust tests to detect many classes of undefined behavior, but treat a clean run as evidence from explored executions, not a proof; Miri itself documents unsupported APIs and incomplete exploration. ([Miri](https://github.com/rust-lang/miri))
- Use the [Unsafe Code Guidelines Reference](https://rust-lang.github.io/unsafe-code-guidelines/) as a design discussion resource, not a stable normative specification; its own introduction marks the material as work in progress. The [Rust Reference](https://doc.rust-lang.org/stable/reference/behavior-considered-undefined.html) remains the primary list of behavior considered undefined.

### Cargo and dependency practice

- Use a workspace for packages that share a lockfile, output directory, commands, and inherited metadata. A virtual workspace has no package edition from which to infer a resolver, so declare the resolver at the root. ([workspaces](https://doc.rust-lang.org/stable/cargo/reference/workspaces.html))
- Keep features additive and avoid mutually exclusive feature designs when possible because Cargo unifies features across dependency edges. Test meaningful feature combinations, especially `--no-default-features` and `--all-features`. ([Cargo features](https://doc.rust-lang.org/stable/cargo/reference/features.html), [feature resolver](https://doc.rust-lang.org/stable/cargo/reference/resolver.html#features))
- Use normal caret dependency requirements with all three components for most dependencies; avoid wildcards and overly broad ranges. Cargo documents these as its general resolver recommendations. ([dependency resolution recommendations](https://doc.rust-lang.org/stable/cargo/reference/resolver.html#recommendations))
- Treat build scripts as host-executed code with explicit rerun inputs and minimal side effects; emit precise `rerun-if-changed`/`rerun-if-env-changed` instructions. ([Cargo build scripts](https://doc.rust-lang.org/stable/cargo/reference/build-scripts.html))
- Separate development and release profile choices and measure them. Cargo documents optimization level, debug info, LTO, codegen units, panic strategy, and incremental compilation in [Profiles](https://doc.rust-lang.org/stable/cargo/reference/profiles.html).
- Use Cargo’s [build timings](https://doc.rust-lang.org/stable/cargo/reference/timings.html) and [build-performance guide](https://doc.rust-lang.org/stable/cargo/guide/build-performance.html) before speculating about slow compilation.

### Testing, linting, formatting, and docs

The following is a strong default CI loop for a workspace. Adapt feature/target flags where `--all-features` creates an unsupported combination; Cargo features are unified and are not always valid simultaneously. ([features](https://doc.rust-lang.org/stable/cargo/reference/features.html))

```bash
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo doc --workspace --no-deps
```

- `cargo fmt --all -- --check` is the rustfmt-documented CI check and exits unsuccessfully when formatting would change. ([rustfmt](https://github.com/rust-lang/rustfmt#checking-style-on-a-ci-server))
- Clippy provides additional correctness, suspicious-code, complexity, performance, and style lints. Review each lint and configure intentional exceptions with narrow scope and a reason instead of blindly allowing whole groups. ([Clippy](https://doc.rust-lang.org/stable/clippy/), [lint configuration](https://doc.rust-lang.org/stable/clippy/configuration.html))
- `cargo test` compiles and runs unit, integration, and documentation tests; doctests run by default for library targets. Keep examples executable as doctests when they express real public API usage. ([`cargo test`](https://doc.rust-lang.org/stable/cargo/commands/cargo-test.html), [rustdoc tests](https://doc.rust-lang.org/stable/rustdoc/write-documentation/documentation-tests.html))
- Put unit tests near private implementation when they need that access, integration tests in `tests/`, and public examples in documentation. Test error cases and invariants, not only happy paths. ([The Book: test organization](https://doc.rust-lang.org/stable/book/ch11-03-test-organization.html))
- Document public APIs with runnable examples, errors, panics, and safety sections where applicable. Use intra-doc links and enable relevant rustdoc lints so refactors do not silently break navigation. ([rustdoc](https://doc.rust-lang.org/stable/rustdoc/how-to-write-documentation.html), [rustdoc lints](https://doc.rust-lang.org/stable/rustdoc/lints.html))

### Performance and security

- Measure representative release builds before optimizing. Debug and release profiles intentionally differ; benchmark/profile the configuration and target users run. ([Cargo profiles](https://doc.rust-lang.org/stable/cargo/reference/profiles.html), [rustc profiling](https://doc.rust-lang.org/stable/rustc/profile-guided-optimization.html))
- Use the compiler’s lint system and Clippy as review aids, not substitutes for tests or domain reasoning. Lint levels are configurable as `allow`, `expect`, `warn`, `force-warn`, `deny`, and `forbid`. ([rustc lint levels](https://doc.rust-lang.org/stable/rustc/lints/levels.html))
- Minimize dependency count and enabled features based on product needs, review transitive dependencies and licenses, and consume vulnerability advisories. The RustSec project maintains the [RustSec Advisory Database and `cargo-audit`](https://rustsec.org/); Cargo’s lockfile and resolver provide repeatability, not a vulnerability guarantee. ([Cargo lockfile](https://doc.rust-lang.org/stable/cargo/guide/cargo-toml-vs-cargo-lock.html))
- Fuzz parsers and externally controlled state machines when malformed input has a meaningful risk. The Rust Fuzz project documents `cargo-fuzz` and its libFuzzer integration in the [Rust Fuzz Book](https://rust-fuzz.github.io/book/).

## Swift–Rust boundary for this repository

This codebase uses SwiftUI above a Rust core through generated UniFFI bindings. The boundary should stay narrower than either internal model:

- Keep ownership, threading, fallibility, and callback lifetime explicit in the interface definition. UniFFI’s user guide covers supported types, objects, async calls, callbacks, and generated foreign-language bindings. ([UniFFI user guide](https://mozilla.github.io/uniffi-rs/latest/))
- Convert Rust panics and Swift traps into neither side’s normal error protocol. Export typed fallible operations and define how cancellation/errors cross the boundary. ([UniFFI error handling](https://mozilla.github.io/uniffi-rs/latest/types/errors.html), [Rust FFI unwinding](https://doc.rust-lang.org/stable/nomicon/ffi.html#ffi-and-unwinding))
- Do not block SwiftUI’s main actor with synchronous foreign work. Swift’s UI state belongs on `MainActor`, while blocking calls need an explicitly owned background execution path and a result applied back under the correct isolation. ([Swift concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/), [SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance))
- Keep generated files reproducible and generated from the authoritative Rust interface; do not hand-edit generated bindings. UniFFI documents its bindgen and library-mode workflows in [Getting started](https://mozilla.github.io/uniffi-rs/latest/Getting_started.html).
- Validate both sides: Rust unit/integration tests for domain and FFI behavior, Swift tests for mapping/model behavior, and UI tests for critical user flows. Neither language’s type system proves that the cross-language representation matches product intent. ([Cargo testing](https://doc.rust-lang.org/stable/cargo/commands/cargo-test.html), [Apple testing](https://developer.apple.com/documentation/xcode/testing))

## Repository implementation status and upgrade plan

The stable upgrade plan was authorized and implemented in this worktree on 2026-08-26. The minimum macOS version was raised to 15.0 on 2026-08-27; prerelease dependencies, preview language modes, approachable-concurrency defaults, and strict-memory-safety mode remain intentionally outside this change.

### Completed upgrade inventory

| Surface | Previous | Current | Behavior protected by tests |
|---|---:|---:|---|
| Swift language mode | 5.10 | **6.0**, complete strict concurrency | Main-actor model/backend tests and a strict-concurrency app build. ([Swift 6 migration](https://www.swift.org/migration/)) |
| `uniffi` | 0.29.5 | **0.32.0** | Rust FFI tests, regenerated Swift/C bindings, and native app/test builds. ([UniFFI releases](https://github.com/mozilla/uniffi-rs/releases)) |
| YAML parser | deprecated `serde_yaml` 0.9.34 | **`serde-saphyr` 1.1.0**, deserialize-only features | Folded values, Unicode, unknown metadata, duplicate required keys, CRLF input, and raw version preservation. ([serde-saphyr](https://github.com/bourumir-wyngs/serde-saphyr)) |
| `notify` | 7.0.0 | **8.2.0** | Real watched-directory create, rename, and delete lifecycle plus relevance/debounce unit tests. ([notify 8.2 docs](https://docs.rs/notify/8.2.0/notify/)) |
| `toml` | 0.8.23 | **1.1.4+spec-1.1.0** | Config defaults, serialization round-trip, legacy `scan_home`, and appearance tests. ([toml documentation](https://docs.rs/toml/latest/toml/)) |
| `ureq` | 2.12.1 | **3.4.0** | Required GitHub headers, JSON response handling, non-retried status errors, and one retry for transport failure. ([ureq 3 migration guide](https://github.com/algesten/ureq/blob/main/MIGRATE-2-to-3.md)) |
| Cargo resolver/toolchain | resolver 2; floating `stable` | **resolver 3; Rust 1.98.0 pin; `rust-version = "1.98"`** | Workspace tests, Clippy, rustfmt, rustdoc, and macOS FFI builds use the same declared baseline. ([Cargo resolver](https://doc.rust-lang.org/stable/cargo/reference/resolver.html#resolver-versions), [Cargo `rust-version`](https://doc.rust-lang.org/stable/cargo/reference/rust-version.html)) |

### Applied sequence and rollback boundaries

1. Record a green Rust and macOS baseline before changing owned files.
2. Replace the deprecated YAML parser behind the existing frontmatter boundary and add compatibility fixtures.
3. Upgrade UniFFI atomically, then regenerate all checked-in Swift/C binding artifacts from the matching generator/runtime.
4. Upgrade the remaining Rust majors, adding explicit HTTP and watcher behavior tests rather than relying on changed library defaults.
5. Enable complete concurrency checking while still in Swift 5 mode, fix the drag-and-drop callback’s real isolation, then switch the authoritative XcodeGen setting to Swift 6.
6. Add a Swift Testing target, regenerate the Xcode project, and validate debug/test/release paths.

Rollback should follow those same ownership boundaries: parser dependency plus compatibility change; UniFFI runtime/generator plus every generated artifact; individual HTTP/watcher/config major; and Swift language-mode/project/isolation changes. Do not hand-edit generated UniFFI output or only the generated Xcode project.

### Remaining follow-up plan

- Add XCUIAutomation coverage for the few critical end-to-end flows: launch/scan, read/edit/save, install, update review/apply, filesystem refresh, cancellation, and visible error projection. Keep Swift Testing for unit/integration coverage and XCTest for UI/performance coverage. ([Xcode testing guidance](https://developer.apple.com/documentation/xcode/testing))
- Add timeout and malformed-response HTTP cases if GitHub networking becomes a higher-risk surface; the current policy is HTTPS-only, a 20-second global timeout, at most five redirects, and one retry only for selected transport failures.
- Keep macOS 15 support until a separate product decision changes it. Availability-gate newer SwiftUI APIs instead of raising the deployment target opportunistically.
- Evaluate approachable-concurrency defaults and strict-memory-safety diagnostics only as separate, reviewable changes. Neither is needed to claim Swift 6 data-race checking. ([Swift 6.2 release](https://www.swift.org/blog/swift-6.2-released/), [strict memory safety](https://docs.swift.org/compiler/documentation/diagnostics/strict-memory-safety/))
- Refresh this page and the exact Rust/Swift pins on the next intentional toolchain upgrade; do not silently follow floating stable or preview documentation.

## Local/offline documentation

### Rust

The default rustup profile includes `rust-docs`, rustfmt, and Clippy. `rustup doc` opens the documentation installed for the selected toolchain, which is the safest offline match for that compiler. ([rustup components](https://rust-lang.github.io/rustup/concepts/components.html), [rustup profiles](https://rust-lang.github.io/rustup/concepts/profiles.html))

```bash
rustup component add rust-docs rustfmt clippy rust-analyzer
rustup doc
rustup doc --book
cargo doc --workspace --no-deps --open
```

### Swift and SwiftUI

Xcode provides SDK symbol documentation for the selected toolchain. For project-owned Swift APIs, DocC can build a documentation archive from source comments, articles, and tutorials; use Xcode’s **Build Documentation** action or the SwiftPM DocC plugin. ([DocC](https://www.swift.org/documentation/docc/), [distributing DocC documentation](https://www.swift.org/documentation/docc/distributing-documentation-to-other-developers))

Apple’s continuously updated SwiftUI web documentation should remain linked rather than copied. A copied framework reference loses availability corrections and new SDK overlays, while the selected Xcode SDK remains the build-time authority.

## Refresh procedure

Repeat this review after a stable Swift release, an Xcode/Apple SDK upgrade, a Rust stable release used by the project, or a deployment-target change:

1. Record `xcodebuild -version`, `xcrun swift --version`, `rustc --version --verbose`, and `cargo --version`.
2. Compare Swift against the [Swift blog](https://www.swift.org/blog/), [language-book displayed version](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/), [Swift Evolution status](https://www.swift.org/swift-evolution/), and [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui).
3. Compare Rust against the [latest release](https://blog.rust-lang.org/releases/latest/), [release notes](https://doc.rust-lang.org/stable/releases.html), [Edition Guide](https://doc.rust-lang.org/stable/edition-guide/), and the project’s MSRV/toolchain policy.
4. Re-run link checking and update the date/version table. Treat redirects to beta/nightly documentation as a reason for manual review, not automatic acceptance.
5. Run the project’s normal Swift and Rust validation with the newly selected toolchains before changing a pinned baseline.

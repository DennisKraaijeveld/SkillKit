# SwiftUI + Rust performance plan for Skillbook

Last reviewed: **2026-08-27**

## Recommendation

Skillbook already has the right high-level ownership split: SwiftUI owns presentation state, a long-lived UniFFI `Session` owns Rust domain state, blocking Rust calls run away from the main actor, and rows have stable domain-derived IDs. The next gains should come from measuring and tightening the existing seams, not from rewriting the Rust core or adding blanket caching, parallelism, or custom allocators.

The highest-priority change to investigate is the idle watcher path. `WorkspaceView` starts one view-lifetime task, but `AppModel.startWatching()` wakes every 160 ms and crosses UniFFI to poll the watcher even when the app is idle ([`WorkspaceView.swift:40`](../macos/Skillbook/Views/WorkspaceView.swift#L40), [`AppModel.swift:387-399`](../macos/Skillbook/AppModel.swift#L387-L399)). Apple explicitly recommends event notifications instead of timers that poll for file-content or other state changes because timer wakeups keep the CPU from remaining idle; Activity Monitor's CPU and Idle Wake Ups columns are the direct acceptance check ([Minimize Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html), [Monitor Usage Regularly](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/MonitoringEnergyUsage.html)). Replace this loop with a Rust-to-Swift change notification or an awaitable “next change” operation if an idle trace confirms recurring wakeups. Do not merely shorten the interval.

The other likely costs are proportional to catalog or document size and therefore need traces before redesign:

- Each configured project or custom root currently runs the recursive `WalkDir` discovery first and then also runs `mdfind` on macOS before merging and deduplicating both result sets ([`scan.rs:144-155`](../crates/skillbook-core/src/scan.rs#L144-L155), [`scan.rs:196-230`](../crates/skillbook-core/src/scan.rs#L196-L230)). This may duplicate directory and metadata work on every full rescan. Measure both phases separately, then keep the dual path only if correctness fixtures prove that neither Spotlight-first with a walk fallback nor targeted known-container discovery can preserve coverage.
- A scan creates a complete `FfiSnapshot`, UniFFI serializes its records, strings, sequences, and optionals into buffers, and Swift then maps the generated records into a second native model graph ([`lib.rs:727-754`](../crates/skillbook-ffi/src/lib.rs#L727-L754), [`RustBackend.swift:51-123`](../macos/Skillbook/RustBackend.swift#L51-L123)). UniFFI documents this lift/lower serialization path and warns that records are copied by value across the FFI ([Lifting, Lowering and Serialization](https://mozilla.github.io/uniffi-rs/latest/internals/lifting_and_lowering.html), [Records](https://mozilla.github.io/uniffi-rs/latest/types/records.html)). One batched snapshot is preferable to a getter per row, but watch rescans should become deltas or generation-based refreshes only if signposts and Allocations show that full snapshots are material.
- `filtered`, `sidebarSections`, duplicate groups, and `dirty` are computed from the whole catalog or document on the main actor; SwiftUI can read them multiple times during an update ([`AppModel.swift:61-63`](../macos/Skillbook/AppModel.swift#L61-L63), [`AppModel.swift:118-139`](../macos/Skillbook/AppModel.swift#L118-L139), [`AppModel.swift:182-200`](../macos/Skillbook/AppModel.swift#L182-L200)). Cache or incrementally maintain a derived value only after the SwiftUI instrument or Time Profiler identifies it as a hot update cause. Apple recommends moving non-UI work out of view updates and reducing dependency breadth, while using Instruments to distinguish long bodies from too-frequent updates ([Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)).
- Markdown parsing is correctly moved off the main actor, but `.task(id:)` cancellation does not cancel the nested detached task; detached tasks have no parent and require manual cancellation ([`MarkdownPreview.swift:132-146`](../macos/Skillbook/Views/MarkdownPreview.swift#L132-L146), [`Task.detached`](https://developer.apple.com/documentation/swift/task/detached%28name%3Apriority%3Aoperation%3A%29-9xki7), [Swift concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)). Rapid document switching can therefore leave obsolete parsing work consuming CPU until it completes. Treat cancellation as a measurable performance feature, not only a UI-state guard.

There is no universal “low memory” or “fast enough” number for this app. Establish repeatable release-build baselines for realistic small, medium, and stress catalogs, then fail regressions against those baselines. Apple recommends the measure-change-remeasure loop and release-configured XCTest performance tests rather than optimizing from intuition ([Improving your app's performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance), [Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)).

## Implementation status

The 2026-08-27 implementation pass completed the changes that were safe to make from code evidence alone:

- The Swift watcher now blocks on a debounced Rust condition variable and is explicitly interruptible when its owning Swift task is cancelled. The event state is coalesced to a single dirty bit, so filesystem bursts cannot grow an unbounded channel.
- Progress is sampled only while a check, update, or installation is active. An idle window no longer runs either 160 ms polling loop.
- Search text, filtered rows, the full and filtered sidebar trees, duplicate groups, update counts, skill lookup, and dirty state now have explicit invalidation owners instead of being rebuilt on every SwiftUI read.
- Obsolete Markdown parse results are cancelled and discarded, silent scans use utility priority, and no-op snapshot fields are not republished.
- Coarse scan, sidebar-projection, and Markdown-parse signposts plus deterministic CPU, clock, and memory performance tests now provide regression hooks.
- The standalone optimized `Skillbook Performance` scheme and machine-specific [`PerformanceBaseline.json`](../macos/PerformanceBaseline.json) enforce the stable clock, CPU-instruction, and Markdown peak-memory measurements; noisy memory deltas remain informational.
- Rust version-state preservation and update-result membership checks use hashed lookup instead of repeated linear scans.

The discovery strategy, FFI snapshot shape, Rust release-profile flags, and MetricKit remain evidence-gated. Changing them without representative Instruments traces or A/B measurements could trade correctness, memory, build time, or diagnosability for an unproven gain.

## Measurement plan

### Scenarios

Capture the same workflows before and after each performance change:

1. Cold launch through first usable catalog and first selected-skill render.
2. Ten seconds idle with the main window visible, then hidden or fully obscured.
3. Search typing and clearing against small, medium, and stress catalogs.
4. Expand/collapse sidebar locations and switch among skills rapidly.
5. Open small and large Markdown files; switch repeatedly before parsing finishes.
6. One watcher event and one burst of create/rename/write events.
7. Manual reload, update check, update preview, apply update, and cancellation.
8. Repeat scan/open/close cycles long enough to distinguish retained memory from temporary peaks.

Use an optimized, symbolicated build that matches the shipping architecture. The Xcode Release build already drives the Rust build script through `cargo build --release`; Cargo's release profile is the optimized production profile ([`build-ffi.sh:32-46`](../macos/scripts/build-ffi.sh#L32-L46), [Cargo profiles](https://doc.rust-lang.org/stable/cargo/reference/profiles.html)). Keep a separate profiling configuration if extra Rust debug information is needed for useful call stacks; do not judge shipping CPU from the unoptimized Debug Rust library.

### Instruments and system tools

| Question | Tool | Skillbook focus |
| --- | --- | --- |
| Which functions consume CPU? | Time Profiler first; Processor Trace or CPU Counters only when the sample points to a lower-level CPU bottleneck. Apple's guidance is to remove redundant work before investigating microarchitectural bottlenecks ([Addressing CPU bottlenecks](https://developer.apple.com/documentation/xcode/addressing-cpu-bottlenecks), [Processor Trace](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace)). | Rust scan/watcher projection, Swift snapshot mapping, `SidebarTree.build`, filtering, dirty composition, Markdown parse and layout. |
| Which SwiftUI dependency causes work? | SwiftUI template plus Time Profiler. The instrument separates update groups, long view bodies, long AppKit representable updates, other layout/text work, and hitches; it also exposes a cause-and-effect graph for frequent invalidation ([Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance), [WWDC25: Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)). | Search typing, progress polling, selection, scroll tracking, settings changes, and catalog replacement. |
| What allocates or remains alive? | Allocations with generation marks, Leaks, and Xcode's memory graph. Allocations reports heap/anonymous-VM count and size; generations isolate one workflow, while the memory graph finds retained object graphs ([Gathering information about memory use](https://developer.apple.com/documentation/Xcode/gathering-information-about-memory-use), [Making changes to reduce memory use](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use)). | RustBuffer lowering/lifting, duplicate Swift model graphs, Markdown `AttributedString` trees, preview/diff rows, and repeated snapshot replacement. |
| Does the idle app really sleep? | Activity Monitor CPU, Energy Impact, App Nap, and Idle Wake Ups; Xcode's Energy Impact gauge during development. Apple's Mac guide says an inactive app should show 0.0 CPU and recommends checking Idle Wake Ups for timer firings ([Monitor Usage Regularly](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/MonitoringEnergyUsage.html), [Minimize Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)). | The 160 ms watch/progress loop is the first controlled comparison. |
| Do concurrency and locks block useful work? | Swift Concurrency instrument and System Trace, then Thread Sanitizer for correctness rather than timing. Apple distinguishes CPU saturation, executor contention, and low-CPU blocking in its Instruments diagnostic flow ([WWDC26: Profile, fix, and verify](https://developer.apple.com/videos/play/wwdc2026/268/), [Diagnosing memory, thread, and crash issues early](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)). | Detached UniFFI calls, overlapping selected-file reads, `Session.inner`, progress locking, and scan/update serialization. |

### Signposts and regression tests

Add `OSSignposter` intervals around logical operations, not every row: `cold-launch`, `scan-rust`, `snapshot-lift-map`, `apply-snapshot`, `sidebar-project`, `markdown-parse`, `markdown-present`, `watch-event-to-visible`, and update/check operations. `OSSignposter` records intervals and events in the unified logging system and the `os_signposts` instrument shows them on the Instruments timeline ([`OSSignposter`](https://developer.apple.com/documentation/os/ossignposter)). Include counts or a generation ID as metadata, but never skill contents or private paths.

Protect stable workloads with XCTest metrics:

- `XCTClockMetric` for elapsed work.
- `XCTCPUMetric` for CPU activity.
- `XCTMemoryMetric` for peak and net allocation growth.
- `XCTOSSignpostMetric` for end-to-end named intervals.
- `XCTApplicationLaunchMetric` for launch once the launch fixture is deterministic.

Apple exposes all of these through XCTest performance tests, recommends a Release build with debugging, coverage, and sanitizers disabled for accurate measurement, and supports stored baselines with failure tolerances ([Performance Tests](https://developer.apple.com/documentation/xctest/performance-tests), [Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests), [Preventing memory-use regressions](https://developer.apple.com/documentation/xcode/preventing-memory-use-regressions)). Keep sanitizers in separate correctness runs because their CPU and memory overhead is intentionally large ([Diagnosing memory, thread, and crash issues early](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)).

MetricKit is useful after distribution, not as a replacement for local profiling. On macOS it provides daily on-device CPU, memory, launch, responsiveness, disk, and diagnostic reports from real use, at most once per day ([MetricKit](https://developer.apple.com/documentation/metrickit), [Monitoring app performance with MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit)). Adopt it only with an explicit storage, privacy, and analysis plan; a local-first app should not start uploading reports merely because the API exists.

## SwiftUI and Swift guidance

### Invalidation and state

`AppModel` uses `@Observable`, which is the appropriate data model for Skillbook's macOS 15 deployment target ([`AppModel.swift:11-13`](../macos/Skillbook/AppModel.swift#L11-L13)). Observation tracks the properties a view actually reads and updates that view when those properties change; an observable object's unrelated property changes do not inherently invalidate a view that never read them ([Managing model data in your app](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app)). Preserve this fine-grained behavior by applying these rules:

- Split a large view when its subregions read unrelated high-frequency state, especially progress, hover position, editor text, and the catalog. Use the SwiftUI cause graph to prove which dependency reaches which view before splitting ([Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)).
- Keep `body` and computed values read from `body` free of disk I/O, FFI calls, Markdown parsing, large sorting/grouping, and avoidable full-string construction. Apple says long or too-frequent bodies cause hitches and resource waste, and recommends asynchronous cached results for expensive calculations ([Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)).
- Normalize the search query once per query change and consider a prepared searchable projection only if Time Profiler identifies repeated lowercase/path work in `filtered`. Do not add a duplicate cache without a clear invalidation owner.
- Compute sidebar projection once when `skills`, `query`, or the filter changes if the trace shows repeated `SidebarTree.build`; keep expansion state separate so opening a disclosure does not rebuild the catalog projection unnecessarily.
- Replace `dirty`'s whole-document recomposition with an edit generation or independently tracked YAML/body equality only if large-document typing shows it on the main-thread profile. Correct unsaved-change semantics remain the first constraint.

### Identity and collections

SwiftUI uses identity to scope view lifetime, state storage, and dependency-graph updates. IDs must be stable and unique; random or position-derived IDs churn state and work ([WWDC21: Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/)). Skillbook's canonical skill IDs and composite placement/skill IDs follow that rule ([`SidebarModel.swift:60-76`](../macos/Skillbook/SidebarModel.swift#L60-L76)). Preserve them across rescans and do not introduce `.id(UUID())`, array-index identity, or whole-list identity resets.

The sidebar already uses `List`, which is conceptually similar to a lazy stack plus a scroll view ([`SidebarView.swift:8-35`](../macos/Skillbook/Views/SidebarView.swift#L8-L35), [Picking container views for your content](https://developer.apple.com/documentation/swiftui/picking-container-views-for-your-content)). Do not replace it with a custom eager stack. For any other large repeated content, Apple recommends starting with a normal stack and moving to `LazyVStack` or `LazyHStack` only when profiling shows a worthwhile benefit; lazy containers trade some layout certainty for on-demand loading ([Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks)).

### Concurrency and cancellation

The main actor should own UI state, not blocking I/O or CPU-heavy parsing. Swift documents the main actor as the serial executor protecting UI data and recommends moving long-running or resource-intensive work away from it ([Swift concurrency: The Main Actor](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html#The-Main-Actor)). Skillbook already runs synchronous UniFFI calls in detached tasks ([`RustBackend.swift:162-170`](../macos/Skillbook/RustBackend.swift#L162-L170), [`RustBackend.swift:286-296`](../macos/Skillbook/RustBackend.swift#L286-L296)); retain the off-main execution, but improve ownership:

- Prefer one explicit backend executor/actor or retained operation handles over creating fire-and-forget detached work at each call site. Apple advises structured concurrency where possible because child cancellation, priority, and task-local values propagate automatically; detached tasks require all of that to be handled manually ([`Task.detached`](https://developer.apple.com/documentation/swift/task/detached%28name%3Apriority%3Aoperation%3A%29-9xki7)).
- Cancel obsolete selected-skill reads and Markdown parses. Swift cancellation is cooperative, so CPU loops and Rust operations need explicit checks; canceling the Swift waiter alone does not stop synchronous Rust or parsing work ([Swift concurrency: Task Cancellation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html#Task-Cancellation), [`Task`](https://developer.apple.com/documentation/swift/task)).
- Keep the view-owned watcher task because SwiftUI cancels a `.task` when its view disappears, but make the operation wait for an event instead of sleeping and polling ([`task(id:)`](https://developer.apple.com/documentation/swiftui/view/task%28id%3Aname%3Apriority%3Afile%3Aline%3A_%3A%29)).
- Keep concurrency bounded. Parallel scans, parses, and update checks can increase CPU and peak memory while competing for the same disk and `Session`; add parallelism only when a profile demonstrates independent work and compare total CPU as well as elapsed time.

### Swift and Foundation memory

Use Allocations and the memory graph to distinguish three different problems: allocation rate, temporary peak memory, and retained-but-unused objects. Leaks only detects unreachable leaked memory; caches or arrays that remain reachable but useless require allocation generations and graph inspection ([Gathering information about memory use](https://developer.apple.com/documentation/Xcode/gathering-information-about-memory-use), [Making changes to reduce memory use](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use)). For Skillbook:

- Avoid retaining both FFI records and mapped Swift records. The current conversion returns only the mapped graph, which is good; verify the temporary RustBuffer and generated values fall after each snapshot.
- Keep only the selected document's parsed Markdown representation unless measurement justifies a bounded cache. If caching is added, give it a byte/count limit and clear ownership.
- Inspect retain cycles in AppKit representables, notification observers, task closures, sheets, and Rust proxy objects after repeated open/close workflows.
- Use a local `autoreleasepool` only around a measured loop that creates many temporary Foundation/AppKit objects. Apple says local pools can reduce peak footprint in such loops; adding pools indiscriminately adds complexity without proving a benefit ([Using Autorelease Pool Blocks](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html)).

## Rust core guidance

### Release configuration

Skillbook's Release Xcode build already selects Cargo's release profile, whose defaults include `opt-level = 3`, no incremental compilation, 16 codegen units, no LTO, and unwind panics ([`build-ffi.sh:32-46`](../macos/scripts/build-ffi.sh#L32-L46), [Cargo profiles](https://doc.rust-lang.org/stable/cargo/reference/profiles.html)). Treat profile changes as measured variants:

1. Keep the current release profile as the control.
2. Compare a custom profile inheriting `release` with `lto = "thin"`.
3. Separately compare fewer codegen units, including `codegen-units = 1`, because Cargo documents that more units improve build parallelism but can produce slower code.
4. Compare wall time, CPU time, peak memory, binary size, and link time. Cargo warns that a higher optimization level is not always faster and size modes are not always smaller ([Cargo `opt-level`](https://doc.rust-lang.org/stable/cargo/reference/profiles.html#opt-level), [Cargo LTO and codegen units](https://doc.rust-lang.org/stable/cargo/reference/profiles.html#lto)).

Do **not** set `panic = "abort"` merely to chase size. Cargo defines abort as terminating the process, while UniFFI catches unwind panics and converts them to unexpected foreign-call errors; UniFFI cannot catch a panic when the panic handler aborts ([Cargo `panic`](https://doc.rust-lang.org/stable/cargo/reference/profiles.html#panic), [UniFFI panic handling](https://mozilla.github.io/uniffi-rs/latest/internals/rust_calls.html#panic-handling)). Keep recoverable failures as exported `Result` values and keep panics out of normal control flow.

`strip` is a binary/debuginfo setting, not a runtime CPU or heap optimization. If distribution size matters, strip only after verifying crash and Instruments symbolication artifacts remain available ([Cargo `strip`](https://doc.rust-lang.org/stable/cargo/reference/profiles.html#strip), [Diagnosing issues using crash reports and device logs](https://developer.apple.com/documentation/xcode/diagnosing-issues-using-crash-reports-and-device-logs)).

### Ownership and allocations

Rust ownership makes drops deterministic, but it does not make cloning or heap allocation free. The Rust book notes that heap allocation requires allocator work and that `clone` can deep-copy heap data ([Ownership](https://doc.rust-lang.org/stable/book/ch04-01-what-is-ownership.html)). Apply that specifically to hot paths:

- Borrow internal `&str`, `&Path`, and slices while data remains inside Rust; only create owned strings and vectors at the UniFFI boundary, which requires supported owned values for records ([References and Borrowing](https://doc.rust-lang.org/stable/book/ch04-02-references-and-borrowing.html), [UniFFI records](https://mozilla.github.io/uniffi-rs/latest/types/records.html)).
- Audit `Inner.config.clone()`, `skills.clone()`, `skill_row` string cloning, `errors.to_vec()`, and version-change projection only when Instruments identifies them. Several are deliberate snapshots that keep slow I/O outside the lock; removing them without a new ownership design could trade allocations for contention ([`lib.rs:233-257`](../crates/skillbook-ffi/src/lib.rs#L233-L257), [`lib.rs:260-277`](../crates/skillbook-ffi/src/lib.rs#L260-L277), [`lib.rs:727-843`](../crates/skillbook-ffi/src/lib.rs#L727-L843)).
- When an output count is known, use `Vec::with_capacity` or `reserve` at measured high-allocation sites. The standard library guarantees the reserved elements can be inserted without reallocation, but speculative over-reservation also increases peak memory ([`Vec::with_capacity`](https://doc.rust-lang.org/stable/std/vec/struct.Vec.html#method.with_capacity), [`Vec::reserve`](https://doc.rust-lang.org/stable/std/vec/struct.Vec.html#method.reserve)).
- Do not introduce `Arc`, `Box`, string interning, a small-vector crate, or a custom allocator without allocation evidence. Each changes representation, ownership, or dependencies and can worsen the workload it was meant to help.

### Locks, threads, and channels

The `Session` design already follows an important rule: clone the scan inputs under `inner`, perform disk/network work without the mutex, then lock again to publish results ([`lib.rs:233-257`](../crates/skillbook-ffi/src/lib.rs#L233-L257)). Preserve that shape. Rust's `Mutex` blocks a waiting thread and remains locked until its guard drops; the standard documentation recommends ending the guard's scope or dropping it before unrelated work ([`Mutex`](https://doc.rust-lang.org/stable/std/sync/struct.Mutex.html)).

Use one `Mutex<Inner>` unless a trace shows meaningful contention. Replacing it with `RwLock`, atomics, or multiple locks can increase complexity and does not eliminate the cost of serializing a full snapshot. If contention is real, split by invariant—for example immutable catalog generation, progress, and watcher signal—and record wait time before and after.

The filesystem watcher currently feeds `std::sync::mpsc::channel`, whose standard documentation describes an asynchronous channel with an effectively infinite buffer ([`watch.rs:19-35`](../crates/skillbook-core/src/watch.rs#L19-L35), [`mpsc::channel`](https://doc.rust-lang.org/stable/std/sync/mpsc/fn.channel.html)). A large event burst can therefore accumulate queued event values until polling drains them. Prefer coalescing “catalog dirty” state or a bounded event design if an event-storm test shows queue growth. A `sync_channel` provides a fixed bound and blocks senders when full, so it is not an automatic drop-in for a filesystem callback; choose backpressure or coalescing semantics deliberately ([`mpsc::sync_channel`](https://doc.rust-lang.org/stable/std/sync/mpsc/fn.sync_channel.html)).

Avoid one native thread per request. Swift's task runtime and the filesystem watcher already provide execution machinery; add a Rust worker pool only if the profile shows parallelizable CPU work. The low-CPU goal is minimum total work and wakeups, not maximum simultaneous execution.

## UniFFI boundary design

Keep the long-lived `Session` object. UniFFI interface objects are Rust structs behind shared references and are passed by reference, whereas records and enums are passed by value ([UniFFI interfaces](https://mozilla.github.io/uniffi-rs/latest/types/interfaces.html)). Skillbook already uses the efficient ownership pattern: Rust retains the canonical graph and Swift sends IDs for mutation instead of reconstructing Rust domain objects ([`swiftui-migration.md:68-78`](swiftui-migration.md#L68-L78)).

For each boundary operation:

- **Batch related work.** `applyUpdates(ids:)` is a good shape: one call carries a list and returns one result list ([`RustBackend.swift:199-202`](../macos/Skillbook/RustBackend.swift#L199-L202)). Do not replace a catalog snapshot with hundreds of row-property calls.
- **Do not over-return.** Split catalog-list fields from selected-detail/update-diff fields if traces show the full `FfiSkillRow` graph dominates scan time or memory. UniFFI serializes strings, optionals, sequences, records, and enums into `RustBuffer` values and deserializes them on the receiving side ([Lifting, Lowering and Serialization](https://mozilla.github.io/uniffi-rs/latest/internals/lifting_and_lowering.html)).
- **Coalesce watch refreshes.** One event burst should produce at most one scan and one Swift publication. If the Rust generation has not changed, return a generation/status instead of a byte-identical full snapshot.
- **Make cancellation cross the boundary.** Skillbook's `cancelJob()` atomic flag is the right pattern for synchronous long-running Rust work ([`AppModel.swift:383-385`](../macos/Skillbook/AppModel.swift#L383-L385), [`lib.rs:260-271`](../crates/skillbook-ffi/src/lib.rs#L260-L271)). Extend explicit cancellation checks to any scan, diff, or update loop shown to outlive its UI owner. The current UniFFI guide says it does not directly map platform-native future cancellation and recommends a library-specific cancellation channel ([UniFFI async/future cancellation](https://mozilla.github.io/uniffi-rs/latest/futures.html#cancelling-async-code)).
- **Keep callbacks sparse.** Report phase or count changes, not every filesystem entry or parsed row. Foreign callbacks are another boundary crossing and exported interfaces must be safe for concurrent access ([UniFFI concurrent interfaces](https://mozilla.github.io/uniffi-rs/latest/types/interfaces.html#concurrent-access)).
- **Retain unwind panics.** An aborting panic terminates the macOS process before UniFFI can translate it; normal operational errors must remain typed `Result` values ([UniFFI foreign-to-Rust calls](https://mozilla.github.io/uniffi-rs/latest/internals/rust_calls.html)).

## Prioritized checklist

### P0 — establish proof

- [ ] Create deterministic small, medium, and stress catalog fixtures and a large Markdown fixture.
- [ ] Capture release-build Time Profiler, SwiftUI, Allocations, Leaks, and ten-second idle Activity Monitor baselines.
- [ ] Add coarse `OSSignposter` intervals spanning Rust execution, UniFFI lift/map, model application, sidebar projection, Markdown parse/present, and watcher latency.
- [ ] Record elapsed, CPU, peak-memory, retained-memory, and idle-wakeup baselines in XCTest where the workload can be deterministic.

### P1 — remove known recurring work

- [ ] Replace the 160 ms watcher/progress polling loop with event-driven delivery; confirm idle CPU reaches 0.0 and Idle Wake Ups fall in Activity Monitor.
- [ ] Coalesce a filesystem event burst to one scan/publication and prevent overlapping silent scans.
- [ ] Retain and cancel obsolete document read/Markdown parse operations; add cooperative cancellation inside CPU-heavy parsing or Rust loops where practical.
- [ ] Use the SwiftUI cause graph to isolate progress, hover, editor, and catalog dependencies; split only the views whose updates are proven to fan out.

### P2 — reduce catalog/document work shown by traces

- [ ] Compute normalized search input once and cache the filtered/sidebar projection by its real inputs if it is a measured hot path.
- [ ] Avoid full document composition on every dirty-state read if large-file typing shows it in the main-thread profile.
- [ ] Signpost recursive walking and Spotlight discovery separately; remove duplicated discovery work only after small, medium, stress, hidden-directory, symlink, and unindexed-root fixtures prove equivalent results.
- [ ] Measure RustBuffer size/time and Swift mapping allocations; if material, return a lightweight catalog plus selected details or watch deltas.
- [ ] Reserve Rust vector capacity only at high-allocation sites with a known output bound.
- [ ] Bound or coalesce watcher-channel state if the event-storm scenario shows queue growth.

### P3 — tune shipping configuration and guard it

- [ ] A/B the current Rust release profile against ThinLTO and fewer codegen units; keep only a repeatable runtime, memory, or binary-size win.
- [ ] Keep `panic = "unwind"` for the UniFFI library and preserve symbolication artifacts.
- [x] Record a machine-specific performance baseline and run it in a stable optimized scheme, separate from sanitizer jobs. Xcode's native baseline can mirror these measurements when its test-result UI is available.
- [ ] Consider MetricKit only when there is a defined on-device report retention, privacy, and review workflow.

## Definition of done

Performance work is complete for a release when the optimized, symbolicated build meets recorded workflow baselines; the idle app shows 0.0 CPU with no recurring app-created wakeup pattern; scan/search/selection/Markdown traces have no unexplained main-actor stalls; repeated workflows return to a stable retained-memory plateau; cancellation stops obsolete expensive work; and every optimization has a before/after trace or performance-test result. These criteria follow Apple's measure, change, and verify cycle and its Mac guidance to make an inactive app genuinely idle ([Improving your app's performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance), [Energy Efficiency Guide for Mac Apps](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/)).

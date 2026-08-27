# macOS SwiftUI app

This is the SkillKit UI. Rust owns scan / updates / watch via `skillbook-ffi`; Swift sends skill **ids**, never reconstructed paths.

## On a Mac

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), `jq`, Rust (`rustup`), and Xcode 16+.

```bash
brew install xcodegen jq
cd macos
xcodegen
open SkillKit.xcodeproj
```

The **Build Rust FFI** phase runs `scripts/build-ffi.sh`: `cargo build -p skillbook-ffi` for every architecture in Xcode's `ARCHS` value (not `uname -m`), UniFFI Swift generation into `Generated/` (files are replaced only when contents change), and a universal `libskillbook_ffi.a` when both arm64 and x86_64 are requested.

Generated Swift (`skillbook.swift`, headers, module map) is committed so Xcode can index the app before the first Rust build. The `.a` is not committed. The app's stable bridging header includes the generated C header; `canImport(skillbookFFI)` is not required.

**Do not enable App Sandbox.** Entitlements turn it off so SkillKit can read `~/.claude/skills` and spawn `npx`/`git`.

## Bindings without Xcode

From the repo root (Linux or macOS):

```bash
./macos/scripts/build-ffi.sh
```

On Linux this only regenerates Swift sources. The static library is produced on macOS.

## Performance baseline

Run the deterministic optimized performance suite on the baseline machine:

```bash
cd macos
./scripts/check-performance-baseline.sh
```

The `SkillKit Performance` scheme uses the optimized, symbolicated `Performance` configuration with the debugger, coverage, and sanitizers disabled. Its standalone test target compiles only the production Markdown and sidebar projection code needed by the fixtures, so unrelated app UI work does not distort or block these measurements.

[`PerformanceBaseline.json`](PerformanceBaseline.json) records three five-iteration runs on the named machine, macOS build, architecture, and Xcode build. The check rejects another environment instead of comparing unlike measurements. It guards elapsed time and retired CPU instructions for both workloads, plus Markdown peak physical memory. Memory deltas and sidebar peak memory remain informational because the baseline run showed too much measurement and process-startup variance.

The same file records a ten-second post-launch idle Time Profiler capture of the exact `Performance` executable. Four 1 ms running samples were observed, about 0.038% sampled CPU, with no app-specific hot stack. Keep workflow traces outside Git; they can include local process metadata and are useful as investigation artifacts rather than portable pass/fail inputs.

When the machine, OS, or Xcode changes, record a new baseline rather than combining results from different environments. To store the same measurements as an Xcode-native baseline, run the `SkillKit Performance` scheme, open the Test navigator, select the performance result, and choose **Set Baseline** from its result control.

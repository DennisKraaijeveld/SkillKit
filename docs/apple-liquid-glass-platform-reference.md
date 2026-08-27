# Apple Liquid Glass and SwiftUI platform reference

Verified against current Apple documentation on **2026-08-27**. This is a concise implementation index for Skillbook, not a mirror of Apple’s copyrighted pages. Follow the links for complete API contracts, examples, and future availability changes.

## Executive summary

- On iOS, iPadOS, macOS, tvOS, and watchOS, standard SwiftUI controls and navigation adopt Liquid Glass automatically when an app uses the current SDK and runs on the current platform release. Apple recommends inspecting that result before building custom glass UI. ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass))
- SwiftUI’s custom Liquid Glass family — including `glassEffect`, `GlassEffectContainer`, `glassEffectID`, transitions, and glass button styles — starts at version 26 on iOS, iPadOS, Mac Catalyst, macOS, tvOS, and watchOS. Apple’s current API availability metadata does **not** list visionOS for this family. ([`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer))
- visionOS has a separate spatial glass system. Standard windows and ornaments already use system glass, while `glassBackgroundEffect` adds a three-dimensional glass background whose physical depth affects z-axis layout. It is not a drop-in substitute for the version-26 Liquid Glass API. ([Bringing your existing apps to visionOS](https://developer.apple.com/documentation/visionos/bringing-your-app-to-visionos), [`glassBackgroundEffect(displayMode:)`](https://developer.apple.com/documentation/swiftui/view/glassbackgroundeffect(displaymode:)))
- Skillbook targets macOS 15, so version-26 APIs must stay behind `if #available(macOS 26.0, *)`, with the native pre-26 UI retained. Do not simulate Liquid Glass on older systems with hard-coded blur, borders, shadows, or colors.

## Platform and device availability

| Device family | System/API support | Platform-specific guidance |
| --- | --- | --- |
| iPhone | Custom SwiftUI Liquid Glass APIs: iOS 26+ | Prefer standard navigation, tab, toolbar, sheet, search, and control APIs. Test touch reactions, safe areas, changing orientations, Dynamic Type, Reduce Motion, and Reduce Transparency. |
| iPad | Custom APIs: iPadOS 26+ | Treat resizable windows, sidebars, inspectors, keyboard, pointer, touch, and Pencil as normal configurations. System search and navigation adapt by size and input mode. |
| Mac | Custom APIs: macOS 26+ | Preserve Mac information density and keyboard behavior. Apple notes that mini, small, and medium controls keep compact rounded-rectangle forms while most standard controls gain slightly more height. |
| Apple TV | Custom APIs: tvOS 26+; the visual effect requires Apple TV 4K (2nd generation) or newer | Adopt the standard focus system. Standard buttons and controls gain Liquid Glass as focus moves; older Apple TV hardware retains the existing appearance. |
| Apple Watch | Custom APIs: watchOS 26+ | The refresh is intentionally minimal and largely automatic, including for apps not rebuilt with the latest SDK. Apple recommends standard toolbar APIs and button styles introduced in watchOS 10 or later. |
| Apple Vision Pro | The version-26 `glassEffect` API family is not listed for visionOS. `glassBackgroundEffect(displayMode:)` is available from visionOS 1.0; the customizable `GlassBackgroundEffect` protocol is available from visionOS 2.4. | Use system windows, toolbars, tab bars, and ornaments. An ornament is already glass by default; borderless buttons can use the system hover treatment. Account for depth, gaze/hover, lighting, viewing distance, and visual comfort. |

The version-26 availability above comes from Apple’s symbol metadata for [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer), [`glassEffectID(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)), [`glassEffectTransition(_:)`](https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)), and the [glass button style](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass). The Apple TV and Apple Watch qualifications come from the platform-considerations section of [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). The Mac control-density changes are demonstrated in [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/); the broader device and input guidance comes from the platform HIG pages indexed below.

## Design rules that apply across platforms

1. **Keep glass in the functional layer.** Apple positions Liquid Glass above content for controls and navigation such as toolbars, tab bars, and sidebars. Use ordinary backgrounds and standard materials within the content layer. ([HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials))
2. **Use native components first.** Build with the current SDK, observe the automatic changes, and customize only where the app has a genuine custom interaction. Native components also adapt automatically to focus, overlap, contrast, transparency, and motion settings. ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass))
3. **Remove competing decoration.** Custom backgrounds behind navigation, split views, tab bars, toolbars, sheets, and popovers can obscure the system material or scroll-edge effect. Review them before adding more effects. ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/))
4. **Use custom glass sparingly.** Too many glass surfaces weaken hierarchy and add rendering cost. Reserve it for important functional elements, not cards, panels, or decorative content. ([HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views))
5. **Prefer `regular` glass.** It is the default and is designed to maintain foreground legibility. Use `clear` only over visually rich media where preserving the media matters, and provide a dimming treatment when contrast requires it. ([HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [`Glass.clear`](https://developer.apple.com/documentation/swiftui/glass/clear))
6. **Use tint semantically.** Tint can communicate prominence or meaning, but Apple advises against using it as decoration. System and semantic colors adapt more reliably to appearance and contrast settings. ([Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/))
7. **Test the real adaptations.** Cover light and dark appearances, Increase Contrast, Reduce Transparency, Reduce Motion, different display content, all supported input methods, window sizes, and device classes. Custom colors and animations need explicit verification even when native controls adapt automatically. ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass))

## SwiftUI API index

| API | Use | Availability |
| --- | --- | --- |
| [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) | Applies configurable Liquid Glass behind a custom view. The default is regular glass in a capsule. The view’s padded bounds determine the glass bounds. | iOS/iPadOS/Mac Catalyst/macOS/tvOS/watchOS 26+ |
| [`Glass`](https://developer.apple.com/documentation/swiftui/glass) | Selects regular, clear, tint, and interactivity configuration. Use [`interactive(_:)`](https://developer.apple.com/documentation/swiftui/glass/interactive(_:)) for a custom control that should react to touch or pointer input. | Same version-26 platforms |
| [`PrimitiveButtonStyle.glass`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass), [`glass(_:)`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass(_:)), and [`glassProminent`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent) | Gives a real `Button` the system glass behavior. Prefer this to manually recreating a glass button. | Same version-26 platforms |
| [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) | Gives nearby glass shapes one sampling/rendering context, improving correctness and performance and enabling blending or morphing. Its spacing controls when shapes begin to merge. | Same version-26 platforms |
| [`glassEffectUnion(id:namespace:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)) | Makes multiple effects with the same identifier, shape, and glass variant contribute to one combined glass shape, including dynamically created views. | Same version-26 platforms |
| [`glassEffectID(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)) | Associates a stable identity in a namespace so corresponding glass shapes can morph during hierarchy transitions. | Same version-26 platforms |
| [`glassEffectTransition(_:)`](https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)) and [`GlassEffectTransition`](https://developer.apple.com/documentation/swiftui/glasseffecttransition) | Chooses the system transition when a glass effect enters or leaves the hierarchy. Use matched geometry for related nearby shapes and materialize for simpler or more distant changes. | Same version-26 platforms |
| [`safeAreaBar(edge:alignment:spacing:content:)`](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)) | Pins a custom control bar beside content while extending the affected scroll view's edge effect beneath it. Prefer it to a `safeAreaInset` plus a hand-built material when a custom bar should participate in the system scroll transition. | iOS/iPadOS/Mac Catalyst/macOS/tvOS/watchOS 26+ |
| [`scrollEdgeEffectStyle(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)) | Tunes the system blur transition between scrolling content and pinned controls. Use one effect per edge: `soft` for a gradual dissolve, `hard` for dense or backgroundless Mac controls that need stronger separation, and the automatic style unless the content proves it insufficient. | Version-26 platforms with Liquid Glass |
| [`scrollEdgeEffectHidden(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:)) | Removes a scroll edge effect for a specified edge when no floating control layer needs separation. Do not hide it merely to recover a pre-version-26 appearance. | Version-26 platforms with Liquid Glass |
| [`glassBackgroundEffect(displayMode:)`](https://developer.apple.com/documentation/swiftui/view/glassbackgroundeffect(displaymode:)) | Adds spatial, three-dimensional glass in visionOS. Because it has physical depth, it participates in z-axis layout. | visionOS 1.0+ only |
| [`GlassBackgroundEffect`](https://developer.apple.com/documentation/swiftui/glassbackgroundeffect) | Defines a custom visionOS spatial glass background effect. | visionOS 2.4+ only |

### Container and transition rules

- Place related glass elements in one `GlassEffectContainer`; separate nearby containers can sample and refract inconsistently.
- Apply `glassEffect` after modifiers that establish the view’s appearance and bounds.
- Give each morphing effect a stable, unique ID inside the same namespace and container.
- `glassEffectID` and `glassEffectTransition` operate when views are inserted, removed, or animated through hierarchy changes; they do not animate arbitrary state by themselves.
- Container spacing is visual behavior, not just layout spacing: increasing it makes shapes begin merging farther apart.
- Avoid many simultaneous effects or containers. Apple explicitly warns that they can reduce rendering performance.

These rules are described together in [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) and demonstrated in [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/).

## Platform-specific implementation notes

### iOS and iPadOS

- Standard `NavigationStack`, `NavigationSplitView`, `TabView`, sheets, popovers, toolbars, search, and controls receive the new appearance from the framework.
- Keep navigation visually distinct from content. Let system bars own their material and scroll-edge treatment instead of placing opaque backgrounds behind them.
- Test every iPad window size and input combination. A design that works by touch at full screen can still crowd under multitasking, keyboard, or pointer use.
- Use `interactive()` for custom touch- or pointer-driven glass controls. A visual-only label does not need an interactive material response.

### macOS

- Preserve keyboard access, native focus behavior, toolbar grouping, and compact control sizes. A decorative focus ring or custom window bar can conflict with these system conventions.
- Use standard toolbar and window APIs wherever possible; remove redundant backgrounds before adding custom glass.
- For a custom bar pinned above a `List` or `ScrollView`, use `safeAreaBar` so the system can size the scroll edge effect around the real controls. Apply at most one `scrollEdgeEffectStyle` per edge and avoid placing an opaque background or second blur over it.
- Pointer feedback should come from a real control. If custom glass is necessary, `interactive()` supplies the material’s pointer response without replacing button semantics.
- Test active/inactive windows, light/dark appearance, long localized labels, narrow windows, Reduce Motion, Reduce Transparency, and Increase Contrast.

### tvOS

- Focus is the primary interaction model. Every actionable item must participate in the standard focus system.
- A standard focused control receives the appropriate system appearance. Use custom glass only if a genuinely custom focusable component cannot be expressed with a standard control.
- Verify focused scaling and spacing from television viewing distance as well as on a development monitor.

### watchOS

- Keep the experience glanceable and shallow. Liquid Glass is a small refinement, not a reason to add surfaces or animation.
- Use standard button and toolbar APIs and validate legibility on the physical display, including Always On and accessibility settings where applicable.

### visionOS

- Do not compile the version-26 Liquid Glass API path for visionOS based solely on a shared SwiftUI source file; Apple’s current symbol availability excludes visionOS.
- Standard visionOS windows use system glass, and system toolbars and tab bars appear as ornaments. Prefer those structures before creating a custom ornament. ([HIG: Ornaments](https://developer.apple.com/design/human-interface-guidelines/ornaments))
- An ornament’s background is glass by default, so additional button borders may be redundant. Let the system provide gaze hover behavior.
- Use `glassBackgroundEffect` only when a custom spatial surface is warranted. Attach it to the complete `ZStack` that needs the effect so SwiftUI can calculate its three-dimensional result correctly.

## Skillbook migration posture

Skillbook is a macOS-only app with a macOS 15 deployment target. The appropriate implementation boundary is:

```swift
if #available(macOS 26.0, *) {
    // Native version-26 Liquid Glass APIs.
} else {
    // Existing native macOS controls and materials.
}
```

For the library sidebar, the version-26 path uses a top `safeAreaBar` and a single soft scroll edge effect. This lets skill rows scroll beneath the pinned maintenance and filter controls without adding a decorative glass panel. The update action uses native glass button styles, becoming prominent only when an update is actually available. The macOS 15 fallback retains the opaque native sidebar surface and bordered button styles.

For the Settings selector specifically:

- Keep one `GlassEffectContainer` around the related tabs.
- Apply glass only to the selected functional element rather than turning the entire settings content into glass.
- Keep a stable ID and namespace for the selected capsule so it can morph between tabs.
- Change selection with a short state transition; when Reduce Motion is enabled, update immediately and use an identity/no-motion transition.
- Keep all panes at a stable window size and preserve real `Button` semantics, native focus, VoiceOver labels, and selected traits.
- Leave the pre-macOS-26 `TabView` path intact. The older system should look native to itself, not like an imitation of macOS 26.

Apple provides [`UIDesignRequiresCompatibility`](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility) as a temporary whole-app escape hatch while reviewing an app built with the latest SDK. It is available for iOS, iPadOS, macOS, and tvOS 26, but Apple says the system ignores it when building for version 27 or later. Skillbook should prefer targeted availability branches and native controls rather than depend on this temporary compatibility mode.

## Validation checklist

- Build and run the version-26 branch on macOS 26 hardware or a current VM.
- Build and run the fallback on macOS 15.
- Verify all panes preserve the same window dimensions and do not add duplicate title/toolbar surfaces.
- Test pointer, keyboard-only navigation, VoiceOver, active/inactive window appearance, and focus indicators.
- Test light, dark, Increase Contrast, Reduce Transparency, and Reduce Motion.
- Exercise repeated tab changes while profiling animation hitches and GPU/rendering cost.
- Recheck this document’s API availability links whenever the project adopts a new Xcode SDK.

## Official Apple source index

### Core design and migration

- [Liquid Glass technology overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [WWDC25: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25: Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [WWDC25: Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [WWDC25: What’s new in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/256/)
- [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass)

### Custom SwiftUI Liquid Glass

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [`Glass`](https://developer.apple.com/documentation/swiftui/glass)
- [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [`glassEffectID(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:))
- [`glassEffectUnion(id:namespace:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:))
- [`glassEffectTransition(_:)`](https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:))
- [`PrimitiveButtonStyle.glass`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass)
- [`PrimitiveButtonStyle.glassProminent`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent)
- [`safeAreaBar(edge:alignment:spacing:content:)`](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:))
- [`scrollEdgeEffectStyle(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:))
- [`ScrollEdgeEffectStyle`](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle)

### Platform design references

- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Designing for iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos)
- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Designing for visionOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-visionos)
- [Human Interface Guidelines: Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)
- [Human Interface Guidelines: Ornaments](https://developer.apple.com/design/human-interface-guidelines/ornaments)
- [Bringing your existing apps to visionOS](https://developer.apple.com/documentation/visionos/bringing-your-app-to-visionos)
- [`glassBackgroundEffect(displayMode:)`](https://developer.apple.com/documentation/swiftui/view/glassbackgroundeffect(displaymode:))
- [`GlassBackgroundEffect`](https://developer.apple.com/documentation/swiftui/glassbackgroundeffect)

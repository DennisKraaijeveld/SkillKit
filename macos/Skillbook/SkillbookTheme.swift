import AppKit
import SwiftUI

enum SkillbookSurfaceLevel: Int, CaseIterable, Sendable {
    case one = 1
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight

    var lightHex: UInt32 {
        switch self {
        case .one: 0xFAFAFA
        case .two: 0xFCFCFC
        case .three, .four, .five, .six, .seven, .eight: 0xFFFFFF
        }
    }

    var darkHex: UInt32 {
        switch self {
        case .one: 0x171717
        case .two: 0x1E1E1E
        case .three: 0x252525
        case .four: 0x2C2C2C
        case .five: 0x333333
        case .six: 0x3A3A3A
        case .seven: 0x414141
        case .eight: 0x484848
        }
    }
}

enum SkillbookTheme {
    static let articleMaxWidth: CGFloat = 720
    static let sourceMaxWidth: CGFloat = 900

    static let segmentedTrack = adaptiveColor(light: 0xEAEAEA, dark: 0x242424)
    static let segmentedHoverFill = adaptiveColor(light: 0xDEDEDE, dark: 0x303030)
    static let segmentedSelectedFill = adaptiveColor(light: 0xFFFFFF, dark: 0x3A3A3A)
    static let segmentedLabel = adaptiveColor(light: 0x4A4A4A, dark: 0xC8C8C8)
    static let segmentedSelectedLabel = adaptiveColor(light: 0x111111, dark: 0xFFFFFF)
    static let segmentedDisabledLabel = adaptiveColor(light: 0x888888, dark: 0x777777)

    @MainActor
    static func applyApplicationAppearance(_ mode: String) {
        NSApplication.shared.appearance = switch mode {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    static func surface(_ level: SkillbookSurfaceLevel) -> Color {
        Color(nsColor: nsSurface(level))
    }

    static func nsSurface(_ level: SkillbookSurfaceLevel) -> NSColor {
        NSColor(name: nil) { appearance in
            rgb(appearance.isDark ? level.darkHex : level.lightHex)
        }
    }

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            rgb(appearance.isDark ? dark : light)
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private struct SkillbookShadowRecipe {
    let primaryRadius: CGFloat
    let primaryY: CGFloat
    let secondaryRadius: CGFloat
    let secondaryY: CGFloat
    let tertiaryRadius: CGFloat
    let tertiaryY: CGFloat

    static func recipe(for level: SkillbookSurfaceLevel) -> Self {
        switch level {
        case .one:
            Self(primaryRadius: 0, primaryY: 0, secondaryRadius: 0, secondaryY: 0, tertiaryRadius: 0, tertiaryY: 0)
        case .two:
            Self(primaryRadius: 0.5, primaryY: 0.5, secondaryRadius: 0, secondaryY: 0, tertiaryRadius: 0, tertiaryY: 0)
        case .three:
            Self(primaryRadius: 1, primaryY: 1, secondaryRadius: 2, secondaryY: 1, tertiaryRadius: 0, tertiaryY: 0)
        case .four:
            Self(primaryRadius: 2, primaryY: 1, secondaryRadius: 4, secondaryY: 2, tertiaryRadius: 0, tertiaryY: 0)
        case .five:
            Self(primaryRadius: 4, primaryY: 2, secondaryRadius: 8, secondaryY: 4, tertiaryRadius: 0, tertiaryY: 0)
        case .six:
            Self(primaryRadius: 8, primaryY: 4, secondaryRadius: 16, secondaryY: 8, tertiaryRadius: 24, tertiaryY: 12)
        case .seven:
            Self(primaryRadius: 12, primaryY: 6, secondaryRadius: 32, secondaryY: 16, tertiaryRadius: 64, tertiaryY: 24)
        case .eight:
            Self(primaryRadius: 24, primaryY: 10, secondaryRadius: 48, secondaryY: 24, tertiaryRadius: 96, tertiaryY: 32)
        }
    }
}

private struct SkillbookSurfaceModifier<SurfaceShape: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let level: SkillbookSurfaceLevel
    let shape: SurfaceShape

    func body(content: Content) -> some View {
        let recipe = SkillbookShadowRecipe.recipe(for: level)
        let dark = colorScheme == .dark
        let primaryShadow = Color.black.opacity(dark ? 0.34 : 0.06)
        let secondaryShadow = Color.black.opacity(dark ? 0.22 : 0.06)
        let tertiaryShadow = Color.black.opacity(dark ? 0.14 : 0.06)

        content
            .background {
                shape.fill(SkillbookTheme.surface(level))
            }
            .overlay {
                shape.stroke(dark ? Color.black.opacity(0.72) : Color.black.opacity(0.06), lineWidth: 1)
                if dark {
                    shape
                        .inset(by: 1)
                        .strokeBorder(Color.white.opacity(0.035), lineWidth: 1)
                    shape
                        .inset(by: 0.5)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.12), .clear, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            }
            .shadow(
                color: recipe.primaryRadius == 0 ? .clear : primaryShadow,
                radius: recipe.primaryRadius,
                y: recipe.primaryY
            )
            .shadow(
                color: recipe.secondaryRadius == 0 ? .clear : secondaryShadow,
                radius: recipe.secondaryRadius,
                y: recipe.secondaryY
            )
            .shadow(
                color: recipe.tertiaryRadius == 0 ? .clear : tertiaryShadow,
                radius: recipe.tertiaryRadius,
                y: recipe.tertiaryY
            )
    }
}

extension View {
    func skillbookSurface<SurfaceShape: InsettableShape>(
        _ level: SkillbookSurfaceLevel,
        in shape: SurfaceShape
    ) -> some View {
        modifier(SkillbookSurfaceModifier(level: level, shape: shape))
    }
}

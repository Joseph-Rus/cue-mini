import SwiftUI

// Editorial design system. Two themes — dark and light — share the same
// semantic tokens so views read `Theme.fg.primary` instead of hex codes.

enum Theme {
    @MainActor
    static var current: ThemePalette {
        switch Settings.shared.appearance {
        case .dark: return .dark
        case .light: return .light
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .dark : .light
        }
    }
}

struct ThemePalette {
    // Surfaces
    let pageBg: Color           // outside the card (transparent in our case, but used for blur fallback)
    let cardBg: Color           // the editorial card
    let cardBorder: Color       // 0.5px hairline

    // Foreground
    let fgPrimary: Color        // titles
    let fgSecondary: Color      // artist, body
    let fgTertiary: Color       // captions, muted
    let fgQuaternary: Color     // disabled / very muted

    // Accents
    let accentMatched: Color    // green confidence dot, "identified" caption
    let accentListening: Color  // pulse, mic listening
    let accentMedium: Color     // medium confidence
    let accentError: Color      // errors

    // Controls
    let controlBg: Color        // default button/input fill
    let controlBgHover: Color
    let controlIconIdle: Color  // bottom-row icon color (idle)
    let controlIconHover: Color

    static let dark = ThemePalette(
        pageBg: Color(red: 0x07/255, green: 0x08/255, blue: 0x0A/255),
        cardBg: Color(red: 0x0E/255, green: 0x0F/255, blue: 0x12/255),
        cardBorder: Color.white.opacity(0.06),

        fgPrimary: Color.white,
        fgSecondary: Color.white.opacity(0.62),
        fgTertiary: Color.white.opacity(0.42),
        fgQuaternary: Color.white.opacity(0.28),

        accentMatched: Color(red: 0x38/255, green: 0xD3/255, blue: 0x9A/255),
        accentListening: Color(red: 0x9A/255, green: 0xA0/255, blue: 0xB4/255),
        accentMedium: Color(red: 0xF5/255, green: 0xC2/255, blue: 0x6B/255),
        accentError: Color(red: 0xFC/255, green: 0xA5/255, blue: 0xA5/255),

        controlBg: Color.white.opacity(0.05),
        controlBgHover: Color.white.opacity(0.10),
        controlIconIdle: Color.white.opacity(0.42),
        controlIconHover: Color.white.opacity(0.85)
    )

    static let light = ThemePalette(
        pageBg: Color(red: 0xF2/255, green: 0xEF/255, blue: 0xE8/255),
        cardBg: Color(red: 0xFA/255, green: 0xF8/255, blue: 0xF3/255),
        cardBorder: Color.black.opacity(0.07),

        fgPrimary: Color(red: 0x0E/255, green: 0x0F/255, blue: 0x12/255),
        fgSecondary: Color(red: 0x0E/255, green: 0x0F/255, blue: 0x12/255).opacity(0.62),
        fgTertiary: Color(red: 0x0E/255, green: 0x0F/255, blue: 0x12/255).opacity(0.45),
        fgQuaternary: Color(red: 0x0E/255, green: 0x0F/255, blue: 0x12/255).opacity(0.28),

        accentMatched: Color(red: 0x10/255, green: 0x9F/255, blue: 0x6E/255),
        accentListening: Color(red: 0x6B/255, green: 0x70/255, blue: 0x82/255),
        accentMedium: Color(red: 0xC9/255, green: 0x8A/255, blue: 0x1A/255),
        accentError: Color(red: 0xC0/255, green: 0x4B/255, blue: 0x4B/255),

        controlBg: Color.black.opacity(0.04),
        controlBgHover: Color.black.opacity(0.08),
        controlIconIdle: Color.black.opacity(0.40),
        controlIconHover: Color.black.opacity(0.78)
    )
}

// MARK: - Typography

enum Typeface {
    /// Display sans (titles). Falls back to SF Pro Rounded if Inter Tight isn't bundled.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if let _ = NSFont(name: "InterTight-Bold", size: size) {
            return .custom("InterTight-Bold", size: size)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    /// Body sans.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let baseName: String
        switch weight {
        case .bold, .heavy, .black: baseName = "InterTight-SemiBold"
        case .semibold: baseName = "InterTight-SemiBold"
        case .medium: baseName = "InterTight-Medium"
        default: baseName = italic ? "InterTight-Italic" : "InterTight-Regular"
        }
        if let _ = NSFont(name: baseName, size: size) {
            return .custom(baseName, size: size)
        }
        var f = Font.system(size: size, weight: weight, design: .default)
        if italic { f = f.italic() }
        return f
    }

    /// Monospaced caption — the "↳ IDENTIFIED" line and confidence number.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .bold, .semibold: name = "JetBrainsMono-SemiBold"
        default: name = "JetBrainsMono-Medium"
        }
        if let _ = NSFont(name: name, size: size) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Reactive theme accessor

@MainActor
final class ThemeObserver: ObservableObject {
    static let shared = ThemeObserver()
    @Published var palette: ThemePalette = Theme.current

    private var appObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    private init() {
        appObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        palette = Theme.current
    }
}

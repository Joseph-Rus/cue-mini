import Foundation
import AppKit

enum Fonts {
    /// Registers all .ttf/.otf files in the bundle's Fonts/ resource directory.
    /// Drop Inter Tight + JetBrains Mono files into Sources/CueMini/Resources/Fonts/
    /// to upgrade the look beyond the SF Pro fallback.
    ///
    /// We resolve the resource bundle defensively — `Bundle.module` traps if the
    /// SwiftPM-generated bundle isn't found at runtime, and the binary may live
    /// in a .app where that path differs. Failing silently here is correct: the
    /// app falls back to system fonts, which are fine.
    static func registerBundled() {
        guard let fontsDir = locateFontsDirectory() else { return }

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: fontsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    private static func locateFontsDirectory() -> URL? {
        // Try common locations in priority order:
        //   1. SwiftPM module bundle (when present)
        //   2. .app/Contents/Resources/Fonts (regular Mac bundle layout)
        //   3. .app/CueMini_CueMini.bundle/Contents/Resources/Fonts (SwiftPM-in-app)

        // 1. SwiftPM bundle — wrap in a do/catch-equivalent because Bundle.module
        //    is a trapping accessor.
        if let swiftpmBundle = swiftpmModuleBundleIfAvailable(),
           let fonts = swiftpmBundle.url(forResource: "Fonts", withExtension: nil) {
            return fonts
        }

        // 2. Standard Resources/Fonts
        if let resources = Bundle.main.resourceURL {
            let fonts = resources.appendingPathComponent("Fonts", isDirectory: true)
            if FileManager.default.fileExists(atPath: fonts.path) {
                return fonts
            }
        }

        return nil
    }

    /// Returns the SwiftPM-generated module bundle if it exists at one of the
    /// known runtime locations. Avoids touching `Bundle.module` directly so the
    /// app cannot trap when the bundle is missing.
    private static func swiftpmModuleBundleIfAvailable() -> Bundle? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("CueMini_CueMini.bundle"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("CueMini_CueMini.bundle"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }
}

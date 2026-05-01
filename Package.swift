// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CueMini",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CueMini", targets: ["CueMini"])
    ],
    targets: [
        .executableTarget(
            name: "CueMini",
            path: "Sources/CueMini",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("ShazamKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)

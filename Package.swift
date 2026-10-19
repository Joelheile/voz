// swift-tools-version:6.2
import PackageDescription

let developerDir = Context.environment["DEVELOPER_DIR"] ?? "/Library/Developer/CommandLineTools"
let testingFrameworkPath = developerDir.hasSuffix("/CommandLineTools")
    ? "\(developerDir)/Library/Developer/Frameworks"
    : "\(developerDir)/Platforms/MacOSX.platform/Developer/Library/Frameworks"

let package = Package(
    name: "voz",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7", traits: []),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.92.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "VozCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Voz",
            dependencies: [
                "VozCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "VozCoreTests",
            dependencies: ["VozCore"],
            swiftSettings: [.unsafeFlags(["-F", testingFrameworkPath])],
            linkerSettings: [.unsafeFlags(["-F", testingFrameworkPath, "-Xlinker", "-rpath", "-Xlinker", testingFrameworkPath])]
        ),
    ]
)

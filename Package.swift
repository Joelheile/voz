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
        .package(url: "https://github.com/ajaxjiang96/lucide-swift.git", exact: "0.9.20"),
    ],
    targets: [
        .executableTarget(
            name: "Voz",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "LucideSwift", package: "lucide-swift"),
            ]
        ),
        .testTarget(
            name: "VozTests",
            dependencies: ["Voz"],
            swiftSettings: [.unsafeFlags(["-F", testingFrameworkPath])],
            linkerSettings: [.unsafeFlags(["-F", testingFrameworkPath, "-Xlinker", "-rpath", "-Xlinker", testingFrameworkPath])]
        ),
    ]
)

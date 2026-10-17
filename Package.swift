// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekFocus",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DeepSeekFocus", targets: ["DeepSeekFocus"])
    ],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath.git", revision: "1d2c90827e9c3908269d810d055fb03b7da5fd53")
    ],
    targets: [
        .target(
            name: "DeepSeekFocusCore",
            path: "Sources/DeepSeekFocusCore"
        ),
        .executableTarget(
            name: "DeepSeekFocus",
            dependencies: ["DeepSeekFocusCore", .product(name: "SwiftMath", package: "SwiftMath")],
            path: "Sources/DeepSeekFocus"
        ),
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["DeepSeekFocusCore"],
            path: "Sources/CoreChecks"
        )
    ]
)

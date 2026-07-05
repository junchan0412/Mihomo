// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mihomo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mihomo", targets: ["Mihomo"]),
        .executable(name: "MihomoHelper", targets: ["MihomoHelper"])
    ],
    targets: [
        .target(
            name: "MihomoShared",
            path: "Sources/MihomoShared"
        ),
        .executableTarget(
            name: "Mihomo",
            dependencies: ["MihomoShared"],
            path: "Sources/Mihomo"
        ),
        .executableTarget(
            name: "MihomoHelper",
            dependencies: ["MihomoShared"],
            path: "Sources/MihomoHelper"
        )
    ]
)

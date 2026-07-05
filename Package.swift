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
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3")
    ],
    targets: [
        .target(
            name: "MihomoShared",
            path: "Sources/MihomoShared"
        ),
        .executableTarget(
            name: "Mihomo",
            dependencies: [
                "MihomoShared",
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/Mihomo"
        ),
        .executableTarget(
            name: "MihomoHelper",
            dependencies: ["MihomoShared"],
            path: "Sources/MihomoHelper"
        )
    ]
)

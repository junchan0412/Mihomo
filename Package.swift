// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mihomo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mihomo", targets: ["Mihomo"])
    ],
    targets: [
        .executableTarget(
            name: "Mihomo",
            path: "Sources/Mihomo"
        )
    ]
)

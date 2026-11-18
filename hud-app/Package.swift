// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dumpling",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Dumpling", targets: ["Dumpling"])
    ],
    targets: [
        .executableTarget(
            name: "Dumpling",
            path: "Sources/Dumpling"
        )
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "which-account",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "which-account", targets: ["WhichAccountApp"])
    ],
    targets: [
        .target(name: "WhichAccountCore"),
        .executableTarget(name: "WhichAccountApp", dependencies: ["WhichAccountCore"]),
        .testTarget(name: "WhichAccountCoreTests", dependencies: ["WhichAccountCore"])
    ]
)

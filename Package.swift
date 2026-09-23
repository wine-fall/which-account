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
        // Everything the app decides and does, behind protocols, with no AppKit —
        // so it can be tested without a window, a GUI session or system settings.
        .target(name: "WhichAccountKit", dependencies: ["WhichAccountCore"]),
        .executableTarget(name: "WhichAccountApp",
                          dependencies: ["WhichAccountCore", "WhichAccountKit"]),
        .testTarget(name: "WhichAccountCoreTests", dependencies: ["WhichAccountCore"]),
        .testTarget(name: "WhichAccountKitTests",
                    dependencies: ["WhichAccountKit", "WhichAccountCore"])
    ]
)

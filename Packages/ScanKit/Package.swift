// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScanKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ScanKit", targets: ["ScanKit"]),
        .executable(name: "scankit-cli", targets: ["scankit-cli"]),
    ],
    targets: [
        .target(name: "ScanKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "scankit-cli",
            dependencies: ["ScanKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScanKitTests",
            dependencies: ["ScanKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

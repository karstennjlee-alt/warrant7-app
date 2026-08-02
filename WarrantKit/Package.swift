// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WarrantKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WarrantKit", targets: ["WarrantKit"])
    ],
    targets: [
        .target(
            name: "WarrantKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WarrantKitTests",
            dependencies: ["WarrantKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

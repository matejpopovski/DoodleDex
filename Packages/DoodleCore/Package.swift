// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DoodleCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DoodleCore", targets: ["DoodleCore"]),
        .library(name: "ParityFixtures", targets: ["ParityFixtures"]),
    ],
    targets: [
        .target(name: "DoodleCore"),
        .target(
            name: "ParityFixtures",
            resources: [
                .copy("Resources/pipeline_fixtures.json"),
                .copy("Resources/model_fixtures.json"),
            ]
        ),
        .testTarget(name: "DoodleCoreTests", dependencies: ["DoodleCore", "ParityFixtures"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Neutron",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NeutronKit", targets: ["NeutronKit"]),
        .executable(name: "neutron", targets: ["neutron"]),
        .executable(name: "NeutronApp", targets: ["NeutronApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "NeutronKit"),
        .executableTarget(
            name: "neutron",
            dependencies: [
                "NeutronKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "NeutronApp",
            dependencies: ["NeutronKit", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "NeutronKitTests", dependencies: ["NeutronKit"]),
    ]
)

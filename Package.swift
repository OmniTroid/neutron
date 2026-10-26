// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Neutron",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NeutronKit", targets: ["NeutronKit"]),
        .executable(name: "neutron", targets: ["neutron"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0"),
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
        .testTarget(name: "NeutronKitTests", dependencies: ["NeutronKit"]),
    ]
)

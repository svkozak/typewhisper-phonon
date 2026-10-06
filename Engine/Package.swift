// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "PhononEngine",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/fermionresearch/phonon-coreml.git", revision: "464ae57460fed61d4feb6f2a7424b5be1213accb"),
    ],
    targets: [
        .executableTarget(name: "PhononSwift", dependencies: [
            .product(name: "PhononCoreML", package: "phonon-coreml"),
        ]),
    ]
)

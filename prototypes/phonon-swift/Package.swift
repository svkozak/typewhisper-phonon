// swift-tools-version:6.2
import PackageDescription
let package = Package(
    name: "PhononSwiftPrototype",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "8d86630ade569728aaea3dc1a29fc44e2efa719b"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3"),
    ],
    targets: [
        .executableTarget(name: "PhononSwift", dependencies: [
            .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
            .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            .product(name: "MLX", package: "mlx-swift"),
        ]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KuehllastCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "KuehllastCore", targets: ["KuehllastCore"])
    ],
    targets: [
        .target(name: "KuehllastCore"),
        .testTarget(name: "KuehllastCoreTests", dependencies: ["KuehllastCore"])
    ]
)

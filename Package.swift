// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Nothinx",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "NothinxKit"),
        .executableTarget(
            name: "Nothinx",
            dependencies: ["NothinxKit"]
        ),
        .testTarget(
            name: "NothinxKitTests",
            dependencies: ["NothinxKit"]
        ),
    ]
)

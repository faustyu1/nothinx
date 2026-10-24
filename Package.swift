// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Nothinx",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "NothinxKit", resources: [.process("Localizable.xcstrings")]),
        .executableTarget(
            name: "Nothinx",
            dependencies: ["NothinxKit"],
            resources: [.process("Localizable.xcstrings"), .process("InfoPlist.xcstrings")]
        ),
        .testTarget(
            name: "NothinxKitTests",
            dependencies: ["NothinxKit"]
        ),
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Taggo",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CTagLib",
            pkgConfig: "taglib_c",
            providers: [.brew(["taglib"])]
        ),
        .executableTarget(
            name: "Taggo",
            dependencies: ["CTagLib"]
        ),
        .testTarget(
            name: "TaggoTests",
            dependencies: ["Taggo"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

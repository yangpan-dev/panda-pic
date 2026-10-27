// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PandaGallery",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PandaGallery", targets: ["PandaGallery"])],
    targets: [
        .executableTarget(name: "PandaGallery", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "PandaGalleryTests", dependencies: ["PandaGallery"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)

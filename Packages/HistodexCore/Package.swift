// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HistodexCore",
    platforms: [.macOS(.v14), .iOS(.v17), .macCatalyst(.v17)],
    products: [.library(name: "HistodexCore", targets: ["HistodexCore"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/facebook/zstd.git", revision: "d9c0c7e2cf8a8bf9fb98d3bee546dcf8dc9ac59a")
    ],
    targets: [
        .target(name: "HistodexCore", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "libzstd", package: "zstd")
        ]),
        .testTarget(name: "HistodexCoreTests", dependencies: ["HistodexCore"])
    ]
)

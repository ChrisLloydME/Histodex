// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HistodexInterface",
    platforms: [.iOS(.v17), .macCatalyst(.v17)],
    products: [.library(name: "HistodexInterface", targets: ["HistodexInterface"])],
    dependencies: [
        .package(path: "../HistodexCore"),
        .package(path: "../LanguageModelChatUI"),
        .package(url: "https://github.com/SnapKit/SnapKit.git", exact: "5.7.1")
    ],
    targets: [.target(name: "HistodexInterface", dependencies: ["HistodexCore", "LanguageModelChatUI", "SnapKit"])]
)

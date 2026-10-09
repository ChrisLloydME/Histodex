// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LanguageModelChatUI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17),
    ],
    products: [
        .library(
            name: "ChatClientKit",
            targets: ["ChatClientKit"]
        ),
        .library(
            name: "LanguageModelChatUI",
            targets: ["LanguageModelChatUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", exact: "1.3.0"),

        .package(url: "https://github.com/Lakr233/ListViewKit", exact: "1.1.8"),
        .package(url: "https://github.com/Lakr233/MarkdownView", exact: "3.7.0"),
        .package(url: "https://github.com/Lakr233/Litext", exact: "1.2.1"),
        .package(url: "https://github.com/SnapKit/SnapKit.git", exact: "5.7.1"),
        .package(url: "https://github.com/mischa-hildebrand/AlignedCollectionViewFlowLayout", exact: "1.1.3"),
        .package(url: "https://github.com/ktiays/GlyphixTextFx/", exact: "2.3.6"),
        .package(url: "https://github.com/alfianlosari/GPTEncoder.git", exact: "1.0.4"),
    ],
    targets: [
        .target(
            name: "ServerEvent",
            path: "Sources/ServerEvent"
        ),
        .target(
            name: "ChatClientKit",
            dependencies: ["ServerEvent"],
            path: "Sources/ChatClientKit"
        ),
        .target(
            name: "LanguageModelChatUI",
            dependencies: [
                "ChatClientKit",
                "ListViewKit",
                "MarkdownView",
                .product(name: "MarkdownParser", package: "MarkdownView"),
                "Litext",
                "SnapKit",
                "AlignedCollectionViewFlowLayout",
                "GlyphixTextFx",
                "GPTEncoder",
            ],
            resources: [.process("Resources")]
        ),
    ]
)

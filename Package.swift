// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Daybrief",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        // The app target (Xcode project) links AppFeature, which transitively pulls the rest.
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "DaybriefCore", targets: ["DaybriefCore"]),
        .library(name: "Pipeline", targets: ["Pipeline"]),
        .library(name: "LLMKit", targets: ["LLMKit"]),
        .library(name: "ConnectorKit", targets: ["ConnectorKit"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Secrets", targets: ["Secrets"]),
    ],
    dependencies: [
        // Plain GRDB for now; the SQLCipher-backed fork is a documented M0 task (see docs/build/grdb-sqlcipher.md).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // MARK: - Foundation

        .target(name: "DaybriefCore"),

        // MARK: - Infrastructure

        .target(name: "Secrets", dependencies: ["DaybriefCore"]),
        .target(
            name: "Persistence",
            dependencies: ["DaybriefCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),

        // MARK: - Connector framework + connectors

        .target(name: "ConnectorKit", dependencies: ["DaybriefCore"]),
        .target(name: "GoogleCalendarConnector", dependencies: ["ConnectorKit", "DaybriefCore"]),
        .target(name: "GmailConnector", dependencies: ["ConnectorKit", "DaybriefCore"]),
        .target(name: "SlackConnector", dependencies: ["ConnectorKit", "DaybriefCore"]),

        // MARK: - Synthesis + render

        .target(name: "LLMKit", dependencies: ["DaybriefCore"]),
        .target(name: "BriefRender", dependencies: ["DaybriefCore"]),

        // MARK: - Orchestration

        .target(
            name: "Pipeline",
            dependencies: ["DaybriefCore", "ConnectorKit", "LLMKit", "BriefRender", "Persistence", "Secrets"]
        ),

        // MARK: - App composition (UI + wiring; only this target is MainActor-isolated)

        .target(
            name: "AppFeature",
            dependencies: [
                "DaybriefCore", "Pipeline", "Persistence", "Secrets", "LLMKit", "BriefRender",
                "ConnectorKit", "GoogleCalendarConnector", "GmailConnector", "SlackConnector",
            ],
            resources: [
                // Ships the editorial serif (Tiempos Text) in `Bundle.module/Fonts` when
                // the licensed `.ttf` files are present locally. They are git-ignored, so
                // the folder may be empty in CI — `DaybriefTheme.registerBundledFonts()`
                // and the type APIs fall back to the system serif gracefully.
                .copy("Fonts"),
            ]
        ),

        // MARK: - Offscreen snapshot tool (renders the brief panel to a PNG via ImageRenderer)

        .executableTarget(
            name: "DaybriefSnapshot",
            dependencies: ["AppFeature", "DaybriefCore", "BriefRender"]
        ),

        // MARK: - Tests

        .testTarget(name: "DaybriefCoreTests", dependencies: ["DaybriefCore"]),
        .testTarget(name: "SecretsTests", dependencies: ["Secrets"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "ConnectorKitTests", dependencies: ["ConnectorKit"]),
        .testTarget(name: "GoogleCalendarConnectorTests", dependencies: ["GoogleCalendarConnector", "ConnectorKit"]),
        .testTarget(name: "GmailConnectorTests", dependencies: ["GmailConnector", "ConnectorKit"]),
        .testTarget(name: "SlackConnectorTests", dependencies: ["SlackConnector", "ConnectorKit"]),
        .testTarget(name: "LLMKitTests", dependencies: ["LLMKit"]),
        .testTarget(name: "BriefRenderTests", dependencies: ["BriefRender", "DaybriefCore"]),
        .testTarget(name: "PipelineTests", dependencies: ["Pipeline", "ConnectorKit", "LLMKit"]),
    ]
)

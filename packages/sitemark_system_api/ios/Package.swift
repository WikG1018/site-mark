// swift-tools-version:5.9
// The pure-logic core of the iOS system bridge: the policy types, the
// publish journal, and the safe publisher. It deliberately excludes the
// Pigeon glue (Classes/SystemApi.g.swift), which imports Flutter and is
// compiled only inside the CocoaPods plugin target (Phase 2b).
import PackageDescription

let package = Package(
    name: "sitemark-system-api-ios",
    targets: [
        .target(
            name: "SiteMarkSystemApiCore",
            path: "Classes",
            exclude: ["SystemApi.g.swift"]
        ),
        .testTarget(
            name: "SiteMarkSystemApiCoreTests",
            dependencies: ["SiteMarkSystemApiCore"],
            path: "Tests"
        ),
    ]
)

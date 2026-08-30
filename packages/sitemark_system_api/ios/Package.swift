// swift-tools-version:5.9
// The pure-logic core of the iOS system bridge: the policy types, the
// publish journal, and the safe publisher. It deliberately excludes the
// Pigeon glue (Classes/SystemApi.g.swift), which imports Flutter and is
// compiled only inside the CocoaPods plugin target (Phase 2b).
import PackageDescription

let package = Package(
    name: "sitemark-system-api-ios",
    // SPM's tools-5.9 default macOS floor (10.13) predates the throwing
    // FileHandle APIs the archive copy path uses (10.15.4+); the pod build
    // keeps its own iOS 14 deployment target from the Xcode project.
    platforms: [
        .macOS(.v13),
        .iOS(.v14),
    ],
    targets: [
        .target(
            name: "SiteMarkSystemApiCore",
            path: "Classes",
            exclude: [
                // Pigeon glue and the Flutter plugin classes import Flutter
                // and are compiled only inside the CocoaPods plugin target.
                "SystemApi.g.swift",
                "SiteMarkSystemPlugin.swift",
                "MemoryPressurePlugin.swift",
                "IOSSystemApi.swift",
            ]
        ),
        .testTarget(
            name: "SiteMarkSystemApiCoreTests",
            dependencies: ["SiteMarkSystemApiCore"],
            path: "Tests"
        ),
    ]
)

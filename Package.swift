// swift-tools-version: 5.9
//
// Kinetikos Tracker SDK for iOS — the package Integrators add in Xcode.
// It holds no source: it points at the pre-built TrackerSDK.xcframework of
// this release, and SwiftPM refuses the download unless its checksum matches.
//
// Generated from tracker-iOS/TrackerSDK/Distribution/Package.swift.template
// by the release steps in RELEASING.md. Don't edit by hand.

import PackageDescription

let package = Package(
    name: "TrackerSDK",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TrackerSDK", targets: ["TrackerSDK"]),
    ],
    targets: [
        .binaryTarget(
            name: "TrackerSDK",
            url: "https://github.com/kinetikosio/tracker-sdk-ios/releases/download/1.0.0-beta.5/TrackerSDK-1.0.0-beta.5.xcframework.zip",
            checksum: "3799a66c9b3773737e1f7c60a7e341b0a9ad2cde77dc52d6cc61c14aac707d4b"
        ),
    ]
)

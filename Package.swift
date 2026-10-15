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
            url: "https://github.com/kinetikosio/tracker-sdk-ios/releases/download/1.0.0-beta.1/TrackerSDK-1.0.0-beta.1.xcframework.zip",
            checksum: "1fe805ff533d2e5d2696252f25eda6d227957fc3674547dc90e1e4d286a85bf3"
        ),
    ]
)

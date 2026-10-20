// swift-tools-version: 5.9

import PackageDescription

// The iOS app is the Xcode project. This package runs the same road math
// and catalog tests on a machine that does not have Xcode.
let package = Package(
    name: "LetterRaceCore",
    targets: [
        .target(
            name: "LetterRaceCore",
            path: "LetterRace/Game",
            exclude: ["TrackView.swift", "TouchCapture.swift"]
        ),
        .testTarget(
            name: "LetterRaceCoreTests",
            dependencies: ["LetterRaceCore"],
            path: "LetterRaceTests"
        ),
    ]
)

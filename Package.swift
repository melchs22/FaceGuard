// swift-tools-version: 5.9
// Package.swift — SPM manifest for FaceGuard (used as fallback build path)
import PackageDescription

let package = Package(
    name: "FaceGuard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FaceGuard",
            path: "FaceGuard",
            sources: ["App", "Camera", "Face", "Security", "UI", "Utilities"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)

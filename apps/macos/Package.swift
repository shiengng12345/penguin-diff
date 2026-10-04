// swift-tools-version: 6.0
import PackageDescription
import Foundation
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
let coreProfile = ProcessInfo.processInfo.environment["CC_CORE_PROFILE"] ?? "debug"
let package = Package(name: "ConfigCompare", platforms: [.macOS(.v14)], products: [.library(name: "CompareShared", targets: ["CompareShared"]), .executable(name: "ConfigCompare", targets: ["ConfigCompare"]), .executable(name: "CompareWorker", targets: ["CompareWorker"])], dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")], targets: [
    .target(name: "CompareShared"),
    .target(name: "CoreFFI", linkerSettings: [.unsafeFlags(["-L", root + "/target/" + coreProfile, "-lcompare_core"])]),
    .target(name: "CoreBridge", dependencies: ["CoreFFI"]),
    .target(name: "CompareUI", dependencies: ["CompareShared", .product(name: "MCP", package: "swift-sdk")], path: "Sources/ConfigCompare"),
    .executableTarget(name: "ConfigCompare", dependencies: ["CompareUI"], path: "Sources/AppEntry"),
    .executableTarget(name: "CompareWorker", dependencies: ["CompareShared", "CoreBridge"]),
    .testTarget(name: "CompareTests", dependencies: ["CompareShared", "CoreBridge", "CompareUI"], path: "Tests", exclude: ["NativeProbes/VaultBindingProbe.swift"], sources: ["CompareTests", "NativeProbes/BackgroundTestWindow.swift"])
])

import CompareUI
import Foundation
import Dispatch
import Darwin
// Keep SwiftUI's blocking event loop outside an async MainActor job so scene
// creation can run. Command-line modes run without constructing an App scene.
if CommandLine.arguments.contains("--mcp") {
    Task { @MainActor in
        exit(await MCPRunner.run())
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--self-test") {
    Task { @MainActor in exit(await PackagedSelfTest.run()) }
    dispatchMain()
} else {
    ConfigCompareApp.main()
}

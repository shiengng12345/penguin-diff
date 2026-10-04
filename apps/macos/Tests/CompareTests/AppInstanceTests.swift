import Testing
@testable import CompareUI

@Suite
struct AppInstanceTests {
    @Test
    func firstInstanceHasNoExistingPeer() {
        #expect(AppInstancePolicy.existingPeer(currentProcessID: 42, peerProcessIDs: []) == nil)
        #expect(AppInstancePolicy.existingPeer(currentProcessID: 42, peerProcessIDs: [42]) == nil)
    }

    @Test
    func duplicateSelectsAnExistingPeerAndIgnoresCurrentProcess() {
        #expect(AppInstancePolicy.existingPeer(currentProcessID: 42, peerProcessIDs: [9, 42, 7]) == 7)
    }

    @Test
    func fallbackOnlyYieldsAnOlderPeer() {
        #expect(AppInstancePolicy.existingPeer(currentProcessID: 7, peerProcessIDs: [9]) == nil)
        #expect(AppInstancePolicy.existingPeer(currentProcessID: 9, peerProcessIDs: [7]) == 7)
    }

    @Test
    func terminatedPeersAreExcludedFromFallback() {
        #expect(AppInstancePolicy.existingPeer(currentProcessID: 9, peerProcessIDs: [7, 9], terminatedProcessIDs: [7]) == nil)
    }

    @Test
    func guardOnlyRunsForThePackagedGuiBundle() {
        #expect(AppInstancePolicy.shouldGuard(bundleIdentifier: "com.penguin.configcompare"))
        #expect(!AppInstancePolicy.shouldGuard(bundleIdentifier: nil))
        #expect(!AppInstancePolicy.shouldGuard(bundleIdentifier: "com.penguin.configcompare.worker"))
    }

    @Test
    func onlyFinishedPeerCanReceiveAHandOff() {
        #expect(AppInstancePolicy.finishedPeer(currentProcessID: 101, peerProcessIDs: [99, 100], finishedProcessIDs: [100]) == 100)
        #expect(AppInstancePolicy.finishedPeer(currentProcessID: 101, peerProcessIDs: [99, 100], finishedProcessIDs: []) == nil)
        #expect(AppInstancePolicy.finishedPeer(currentProcessID: 7, peerProcessIDs: [9], finishedProcessIDs: [9]) == 9)
    }
}

import Foundation
import Testing
@testable import bitlocal

@MainActor
@Suite(.tags(.persistence))
final class SavedPlacesStoreTests {
    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        suiteName = "SavedPlacesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test func toggleSavedPersistsAcrossInstances() {
        let store = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        #expect(store.isSaved("place-1") == false)

        store.toggleSaved("place-1")
        #expect(store.isSaved("place-1"))
        #expect(store.savedIDs == ["place-1"])
        #expect(store.pendingAdditionIDs == ["place-1"])
        #expect(store.pendingRemovalIDs.isEmpty)

        // Fresh store instance reading the same defaults should restore saved IDs and pending queues.
        let reloaded = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        #expect(reloaded.isSaved("place-1"))
        #expect(reloaded.pendingAdditionIDs == ["place-1"])
    }

    @Test func toggleUnsaveMovesPlaceFromPendingAdditionsToPendingRemovals() {
        let store = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        store.toggleSaved("place-42")
        #expect(store.pendingAdditionIDs == ["place-42"])

        store.toggleSaved("place-42")
        #expect(store.isSaved("place-42") == false)
        #expect(store.pendingAdditionIDs.isEmpty)
        #expect(store.pendingRemovalIDs == ["place-42"])

        // Re-saving removes from pendingRemovals and re-queues in pendingAdditions.
        store.toggleSaved("place-42")
        #expect(store.isSaved("place-42"))
        #expect(store.pendingAdditionIDs == ["place-42"])
        #expect(store.pendingRemovalIDs.isEmpty)
    }

    @Test func toggleIgnoresEmptyPlaceID() {
        let store = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        store.toggleSaved("")
        #expect(store.savedIDs.isEmpty)
        #expect(store.pendingAdditionIDs.isEmpty)
        #expect(store.pendingRemovalIDs.isEmpty)
    }

    @Test func applyCloudMergeAddsRemoteIDsWithoutResurrectingPendingRemovals() {
        let store = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        store.toggleSaved("local-only")
        store.toggleSaved("deleted-locally")
        store.toggleSaved("deleted-locally") // Now in pendingRemovals

        store.applyCloudMerge(remoteIDs: ["remote-new", "deleted-locally", "local-only"])

        #expect(store.savedIDs == ["local-only", "remote-new"])
        #expect(store.isSaved("deleted-locally") == false)

        // Verify merged set was persisted.
        let reloaded = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        #expect(reloaded.savedIDs == ["local-only", "remote-new"])
    }
}

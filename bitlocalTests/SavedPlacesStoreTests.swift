import XCTest
@testable import bitlocal

@MainActor
final class SavedPlacesStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SavedPlacesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testToggleSavedPersistsAcrossInstances() {
        let store = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        XCTAssertFalse(store.isSaved("place-1"))

        store.toggleSaved("place-1")
        XCTAssertTrue(store.isSaved("place-1"))
        XCTAssertEqual(store.savedIDs, ["place-1"])
        XCTAssertEqual(store.pendingAdditionIDs, ["place-1"])
        XCTAssertTrue(store.pendingRemovalIDs.isEmpty)

        // Fresh store instance reading the same defaults should restore saved IDs and pending queues.
        let reloaded = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        XCTAssertTrue(reloaded.isSaved("place-1"))
        XCTAssertEqual(reloaded.pendingAdditionIDs, ["place-1"])
    }

    func testToggleUnsaveMovesPlaceFromPendingAdditionsToPendingRemovals() {
        let store = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        store.toggleSaved("place-42")
        XCTAssertEqual(store.pendingAdditionIDs, ["place-42"])

        store.toggleSaved("place-42")
        XCTAssertFalse(store.isSaved("place-42"))
        XCTAssertTrue(store.pendingAdditionIDs.isEmpty)
        XCTAssertEqual(store.pendingRemovalIDs, ["place-42"])

        // Re-saving removes from pendingRemovals and re-queues in pendingAdditions.
        store.toggleSaved("place-42")
        XCTAssertTrue(store.isSaved("place-42"))
        XCTAssertEqual(store.pendingAdditionIDs, ["place-42"])
        XCTAssertTrue(store.pendingRemovalIDs.isEmpty)
    }

    func testToggleIgnoresEmptyPlaceID() {
        let store = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        store.toggleSaved("")
        XCTAssertTrue(store.savedIDs.isEmpty)
        XCTAssertTrue(store.pendingAdditionIDs.isEmpty)
        XCTAssertTrue(store.pendingRemovalIDs.isEmpty)
    }

    func testApplyCloudMergeAddsRemoteIDsWithoutResurrectingPendingRemovals() {
        let store = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        store.toggleSaved("local-only")
        store.toggleSaved("deleted-locally")
        store.toggleSaved("deleted-locally") // Now in pendingRemovals

        store.applyCloudMerge(remoteIDs: ["remote-new", "deleted-locally", "local-only"])

        XCTAssertEqual(store.savedIDs, ["local-only", "remote-new"])
        XCTAssertFalse(store.isSaved("deleted-locally"))

        // Verify merged set was persisted.
        let reloaded = SavedPlacesStore(userDefaults: defaults, enableCloudKitSync: false)
        XCTAssertEqual(reloaded.savedIDs, ["local-only", "remote-new"])
    }
}

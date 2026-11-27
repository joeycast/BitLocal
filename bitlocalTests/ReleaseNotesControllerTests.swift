import Foundation
import Testing
@testable import bitlocal

@MainActor
@Suite(.tags(.persistence))
final class ReleaseNotesControllerTests {
    private let suiteName = "ReleaseNotesControllerTests-\(UUID().uuidString)"

    init() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test func showsReleaseNotesForUnseenMeaningfulVersion() {
        let defaults = testDefaults()
        defaults.set("2.9", forKey: "lastSeenReleaseNotesVersion")
        let controller = makeController(currentVersion: "3.0", defaults: defaults)

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        #expect(controller.activeReleaseNotes?.version == "3.0")
    }

    @Test func skipsReleaseNotesOnFirstLaunchAndMarksVersionSeen() {
        let defaults = testDefaults()
        let controller = makeController(currentVersion: "3.0", defaults: defaults)

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        #expect(controller.activeReleaseNotes == nil)
        #expect(defaults.string(forKey: "lastSeenReleaseNotesVersion") == "3.0")
    }

    @Test func skipsReleaseNotesWhenVersionWasAlreadySeen() {
        let defaults = testDefaults()
        defaults.set("3.0", forKey: "lastSeenReleaseNotesVersion")
        let controller = makeController(currentVersion: "3.0", defaults: defaults)

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        #expect(controller.activeReleaseNotes == nil)
    }

    @Test func skipsReleaseNotesForVersionsWithoutAnEntry() {
        let controller = makeController(currentVersion: "3.0.1")

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        #expect(controller.activeReleaseNotes == nil)
    }

    @Test func dismissMarksVersionAsSeen() {
        let defaults = testDefaults()
        let controller = makeController(currentVersion: "3.0", defaults: defaults)

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)
        controller.dismiss()

        #expect(defaults.string(forKey: "lastSeenReleaseNotesVersion") == "3.0")
        #expect(controller.activeReleaseNotes == nil)
    }

    private func makeController(
        currentVersion: String,
        defaults: UserDefaults? = nil
    ) -> ReleaseNotesController {
        ReleaseNotesController(
            userDefaults: defaults ?? testDefaults(),
            currentVersion: currentVersion
        )
    }

    private func testDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults suite for tests")
        }
        return defaults
    }
}

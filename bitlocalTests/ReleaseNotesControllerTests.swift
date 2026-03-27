import XCTest
@testable import bitlocal

@MainActor
final class ReleaseNotesControllerTests: XCTestCase {
    private let suiteName = "ReleaseNotesControllerTests"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testShowsReleaseNotesForUnseenMeaningfulVersion() {
        let defaults = testDefaults()
        defaults.set("2.9", forKey: "lastSeenReleaseNotesVersion")
        let controller = makeController(currentVersion: "3.0", defaults: defaults)

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        XCTAssertEqual(controller.activeReleaseNotes?.version, "3.0")
    }

    func testSkipsReleaseNotesOnFirstLaunchAndMarksVersionSeen() {
        let defaults = testDefaults()
        let controller = makeController(currentVersion: "3.0", defaults: defaults)

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        XCTAssertNil(controller.activeReleaseNotes)
        XCTAssertEqual(defaults.string(forKey: "lastSeenReleaseNotesVersion"), "3.0")
    }

    func testSkipsReleaseNotesWhenVersionWasAlreadySeen() {
        let defaults = testDefaults()
        defaults.set("3.0", forKey: "lastSeenReleaseNotesVersion")
        let controller = makeController(currentVersion: "3.0", defaults: defaults)

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        XCTAssertNil(controller.activeReleaseNotes)
    }

    func testSkipsReleaseNotesForVersionsWithoutAnEntry() {
        let controller = makeController(currentVersion: "3.0.1")

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        XCTAssertNil(controller.activeReleaseNotes)
    }

    func testDismissMarksVersionAsSeen() {
        let defaults = testDefaults()
        let controller = makeController(currentVersion: "3.0", defaults: defaults)

        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)
        controller.dismiss()

        XCTAssertEqual(defaults.string(forKey: "lastSeenReleaseNotesVersion"), "3.0")
        XCTAssertNil(controller.activeReleaseNotes)
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

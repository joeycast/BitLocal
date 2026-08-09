import XCTest
@testable import bitlocal

@MainActor
final class FeatureHintsControllerTests: XCTestCase {
    private let suiteName = "FeatureHintsControllerTests"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.set(true, forKey: FeatureFlags.featureHintsKey)
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeObject(forKey: FeatureFlags.featureHintsKey)
        super.tearDown()
    }

    func testShowsCurrentCampaignWhenUnseenAndEligible() {
        let controller = makeController()

        controller.markMainUIVisible()
        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        XCTAssertEqual(controller.activeTarget, .merchantSearch)
    }

    func testSkipsAutomaticPresentationWhenCampaignAlreadySeen() {
        let defaults = testDefaults()
        defaults.set(FeatureHintCampaign.current.id, forKey: "lastSeenHintCampaignID")
        let controller = FeatureHintsController(userDefaults: defaults)

        controller.markMainUIVisible()
        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        XCTAssertFalse(controller.isPresenting)
    }

    func testManualReplayOverridesSeenCampaign() {
        let defaults = testDefaults()
        defaults.set(FeatureHintCampaign.current.id, forKey: "lastSeenHintCampaignID")
        let controller = FeatureHintsController(userDefaults: defaults)

        controller.scheduleReplay()
        controller.markMainUIVisible()
        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        XCTAssertEqual(controller.activeTarget, .merchantSearch)
    }

    func testSkipMarksCampaignAsSeen() {
        let defaults = testDefaults()
        let controller = FeatureHintsController(userDefaults: defaults)

        controller.markMainUIVisible()
        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)
        controller.skip()

        XCTAssertEqual(
            defaults.string(forKey: "lastSeenHintCampaignID"),
            FeatureHintCampaign.current.id
        )
        XCTAssertFalse(controller.isPresenting)
    }

    private func makeController() -> FeatureHintsController {
        FeatureHintsController(userDefaults: testDefaults())
    }

    private func testDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults suite for tests")
        }
        return defaults
    }
}

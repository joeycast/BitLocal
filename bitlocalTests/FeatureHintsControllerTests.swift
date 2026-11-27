import Foundation
import Testing
@testable import bitlocal

@MainActor
@Suite(.serialized, .tags(.persistence))
final class FeatureHintsControllerTests {
    private let suiteName = "FeatureHintsControllerTests-\(UUID().uuidString)"

    init() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.set(true, forKey: FeatureFlags.featureHintsKey)
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeObject(forKey: FeatureFlags.featureHintsKey)
    }

    @Test func showsCurrentCampaignWhenUnseenAndEligible() {
        let controller = makeController()

        controller.markMainUIVisible()
        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        #expect(controller.activeTarget == .merchantSearch)
    }

    @Test func skipsAutomaticPresentationWhenCampaignAlreadySeen() {
        let defaults = testDefaults()
        defaults.set(FeatureHintCampaign.current.id, forKey: "lastSeenHintCampaignID")
        let controller = FeatureHintsController(userDefaults: defaults)

        controller.markMainUIVisible()
        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        #expect(controller.isPresenting == false)
    }

    @Test func manualReplayOverridesSeenCampaign() {
        let defaults = testDefaults()
        defaults.set(FeatureHintCampaign.current.id, forKey: "lastSeenHintCampaignID")
        let controller = FeatureHintsController(userDefaults: defaults)

        controller.scheduleReplay()
        controller.markMainUIVisible()
        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)

        #expect(controller.activeTarget == .merchantSearch)
    }

    @Test func skipMarksCampaignAsSeen() {
        let defaults = testDefaults()
        let controller = FeatureHintsController(userDefaults: defaults)

        controller.markMainUIVisible()
        controller.evaluatePresentation(didCompleteOnboarding: true, isReadyForMainUI: true)
        controller.skip()

        #expect(defaults.string(forKey: "lastSeenHintCampaignID") == FeatureHintCampaign.current.id)
        #expect(controller.isPresenting == false)
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

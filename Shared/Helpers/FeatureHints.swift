import Combine
import Foundation
import SwiftUI

enum FeatureHintTarget: String, Hashable {
    case merchantSearch
    case communityToggle
    case merchantAlerts
}

enum FeatureHintCardPlacement {
    case automatic
    case above
    case below
}

struct FeatureHintStep: Identifiable, Equatable {
    let target: FeatureHintTarget
    let title: String
    let message: String
    let primaryButtonTitle: String
    let preferredCardPlacement: FeatureHintCardPlacement

    var id: FeatureHintTarget { target }
}

struct FeatureHintCampaign: Equatable {
    let id: String
    let steps: [FeatureHintStep]

    static let current = FeatureHintCampaign(
        id: "v1",
        steps: [
            FeatureHintStep(
                target: .merchantSearch,
                title: String(localized: "Search for places"),
                message: String(localized: "Find businesses by name or category, like \"coffee\" or \"ATM\"."),
                primaryButtonTitle: String(localized: "Next"),
                preferredCardPlacement: .below
            ),
            FeatureHintStep(
                target: .communityToggle,
                title: String(localized: "Find communities"),
                message: String(localized: "Tap here to see bitcoin communities near you."),
                primaryButtonTitle: String(localized: "Next"),
                preferredCardPlacement: .below
            ),
            FeatureHintStep(
                target: .merchantAlerts,
                title: String(localized: "Stay in the loop"),
                message: String(localized: "Turn on Merchant Alerts to get notified when new bitcoin-friendly places open in your city."),
                primaryButtonTitle: String(localized: "Done"),
                preferredCardPlacement: .above
            ),
        ]
    )
}

@MainActor
final class FeatureHintsController: ObservableObject {
    private enum StorageKey {
        static let lastSeenHintCampaignID = "lastSeenHintCampaignID"
        static let shouldReplayHints = "shouldReplayHints"
    }

    @Published private(set) var activeCampaign: FeatureHintCampaign?
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var replayRequestCount = 0
    @Published private(set) var mainUIPresentationCount = 0

    private let userDefaults: UserDefaults
    private var targetFrames: [FeatureHintTarget: CGRect] = [:]
    private var overlayWindow: UIWindow?
    private var overlayWindowCancellable: AnyCancellable?
    private var hasObservedMainUI = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var activeStep: FeatureHintStep? {
        guard let activeCampaign, activeCampaign.steps.indices.contains(currentStepIndex) else {
            return nil
        }

        return activeCampaign.steps[currentStepIndex]
    }

    var activeTarget: FeatureHintTarget? {
        activeStep?.target
    }

    var isPresenting: Bool {
        activeCampaign != nil
    }

    var primaryButtonTitle: String {
        activeStep?.primaryButtonTitle ?? "Done"
    }

    func updateFrame(target: FeatureHintTarget, frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        let existing = targetFrames[target]
        targetFrames[target] = frame
        // Notify observers when a frame first appears or moves significantly,
        // so the overlay re-renders (targetFrames is not @Published to avoid
        // excessive re-renders during animations).
        if existing == nil || !framesAreClose(existing!, frame) {
            objectWillChange.send()
        }
    }

    func clearFrame(target: FeatureHintTarget) {
        guard targetFrames.removeValue(forKey: target) != nil else { return }
        objectWillChange.send()
    }

    private func framesAreClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 &&
        abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    func frame(for target: FeatureHintTarget) -> CGRect? {
        targetFrames[target]
    }

    func evaluatePresentation(didCompleteOnboarding: Bool, isReadyForMainUI: Bool) {
        guard FeatureFlags.isFeatureHintsEnabled else {
            finish(markCampaignSeen: false)
            return
        }
        guard !isPresenting else { return }
        guard didCompleteOnboarding, isReadyForMainUI, hasObservedMainUI else { return }

        if userDefaults.bool(forKey: StorageKey.shouldReplayHints) {
            userDefaults.set(false, forKey: StorageKey.shouldReplayHints)
            beginCurrentCampaign()
            return
        }

        guard userDefaults.string(forKey: StorageKey.lastSeenHintCampaignID) != FeatureHintCampaign.current.id else {
            return
        }

        beginCurrentCampaign()
    }

    func scheduleReplay() {
        guard FeatureFlags.isFeatureHintsEnabled else { return }
        userDefaults.set(true, forKey: StorageKey.shouldReplayHints)
        replayRequestCount += 1
    }

    func markMainUIVisible() {
        guard FeatureFlags.isFeatureHintsEnabled else { return }
        guard !hasObservedMainUI else { return }
        hasObservedMainUI = true
        mainUIPresentationCount += 1
        Debug.logTiming("onboarding", "feature hints main UI visibility observed")
    }

    func advance() {
        guard let activeCampaign else { return }

        let nextIndex = currentStepIndex + 1
        guard nextIndex < activeCampaign.steps.count else {
            finish(markCampaignSeen: true)
            return
        }

        currentStepIndex = nextIndex
    }

    func skip() {
        finish(markCampaignSeen: true)
    }

    // MARK: - Overlay window

    func installOverlayWindow() {
        guard FeatureFlags.isFeatureHintsEnabled else { return }
        guard overlayWindow == nil,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        let overlay = FeatureHintsOverlay()
            .environmentObject(self)

        let hosting = UIHostingController(rootView: overlay)
        hosting.view.backgroundColor = .clear

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = hosting
        window.isUserInteractionEnabled = false
        window.isHidden = false

        self.overlayWindow = window

        overlayWindowCancellable = $activeCampaign
            .sink { [weak window] campaign in
                window?.isUserInteractionEnabled = (campaign != nil)
            }
    }

    // MARK: - Private

    private func beginCurrentCampaign() {
        activeCampaign = FeatureHintCampaign.current
        currentStepIndex = 0
    }

    private func finish(markCampaignSeen: Bool) {
        if markCampaignSeen {
            userDefaults.set(FeatureHintCampaign.current.id, forKey: StorageKey.lastSeenHintCampaignID)
            userDefaults.set(false, forKey: StorageKey.shouldReplayHints)
        }

        activeCampaign = nil
        currentStepIndex = 0
    }
}

// MARK: - Anchor modifier (UIKit-based for reliability across sheet presentations)

private struct FeatureHintAnchorModifier: ViewModifier {
    @EnvironmentObject private var featureHintsController: FeatureHintsController
    let target: FeatureHintTarget

    func body(content: Content) -> some View {
        content
            .background(
                FrameReporter(target: target, controller: featureHintsController)
            )
            .onDisappear {
                featureHintsController.clearFrame(target: target)
            }
    }
}

/// UIKit-based frame reporter that fires on every layout pass, including during sheet animations.
private struct FrameReporter: UIViewRepresentable {
    let target: FeatureHintTarget
    let controller: FeatureHintsController

    func makeUIView(context: Context) -> FrameReporterView {
        let view = FrameReporterView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.target = target
        view.controller = controller
        return view
    }

    func updateUIView(_ uiView: FrameReporterView, context: Context) {
        uiView.target = target
        uiView.controller = controller
    }
}

private class FrameReporterView: UIView {
    var target: FeatureHintTarget?
    weak var controller: FeatureHintsController?

    override func layoutSubviews() {
        super.layoutSubviews()
        reportFrame()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportFrame()
    }

    private func reportFrame() {
        guard let target, let controller, window != nil else { return }
        let screenFrame = convert(bounds, to: nil)
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }
        Task { @MainActor in
            controller.updateFrame(target: target, frame: screenFrame)
        }
    }
}

extension View {
    func featureHintAnchor(_ target: FeatureHintTarget) -> some View {
        modifier(FeatureHintAnchorModifier(target: target))
    }
}

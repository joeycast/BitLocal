import Combine
import SwiftUI
import UIKit

/// Isolated sheet-height state so detent dragging does not invalidate the entire
/// `ContentViewModel` observation graph on every geometry tick.
@MainActor
final class SheetGeometryModel: ObservableObject {
    /// Continuous height (screen bottom → sheet top). Not `@Published`.
    /// Map chrome should subscribe via `continuousHeightPublisher` so list bodies
    /// are not re-evaluated every frame.
    private(set) var continuousHeight: CGFloat = 0

    /// Sparse SwiftUI-facing height for collapsed-content reveal only.
    /// Publishes only near the collapsed band, not on every drag frame.
    @Published private(set) var liveHeight: CGFloat = 0

    /// Height captured when a detent selection settles. Not observable: callers
    /// read it synchronously so drag-time measurements never fan out through SwiftUI.
    private(set) var settledHeight: CGFloat = 0

    /// High-frequency continuous height for UIKit chrome (not objectWillChange).
    let continuousHeightPublisher = PassthroughSubject<CGFloat, Never>()

    private var lastLivePublished: CGFloat = -1
    private var lastContinuousSent: CGFloat = -1

    /// Only publish `liveHeight` for SwiftUI when near collapsed reveal.
    private static let revealPublishCeiling: CGFloat = 200
    private static let livePublishThreshold: CGFloat = 2
    private static let continuousSendThreshold: CGFloat = 0.5

    /// Continuous measurement while the sheet moves.
    /// - Parameter height: Distance from screen bottom → sheet top (global coordinates).
    func reportMeasuredHeight(_ height: CGFloat) {
        guard height > 1 else { return }

        continuousHeight = height
        if lastContinuousSent < 0 || abs(height - lastContinuousSent) >= Self.continuousSendThreshold {
            lastContinuousSent = height
            continuousHeightPublisher.send(height)
        }

        // SwiftUI list/detail only need live height near collapsed reveal.
        // Publishing every frame while expanded re-draws list chrome for no benefit.
        if height <= Self.revealPublishCeiling {
            if lastLivePublished < 0 || abs(height - lastLivePublished) >= Self.livePublishThreshold {
                lastLivePublished = height
                liveHeight = height
            }
        } else if liveHeight != 0, lastLivePublished >= 0, lastLivePublished <= Self.revealPublishCeiling {
            // Left the reveal band: one final full-reveal publish, then stay quiet.
            lastLivePublished = height
            liveHeight = height
        }
    }

    /// Update settled height when a detent selection settles.
    /// Does **not** overwrite continuous tracking from estimates.
    func reportDetentSettledHeight(_ height: CGFloat) {
        guard height > 1 else { return }
        let resolved = continuousHeight > 1 ? continuousHeight : height
        settledHeight = resolved
        // Align continuous + sparse live to the settled value once.
        continuousHeight = resolved
        lastContinuousSent = resolved
        continuousHeightPublisher.send(resolved)
        if abs(liveHeight - resolved) > 0.5 {
            lastLivePublished = resolved
            liveHeight = resolved
        }
    }
}

// MARK: - Global sheet-edge reader

/// Reports the visible sheet card's distance from the bottom of the screen using
/// UIKit layout passes. More reliable than SwiftUI content-height during interactive
/// detent changes, and matches what map chrome should clear.
struct SheetEdgeHeightReader: UIViewRepresentable {
    var onHeightChange: (CGFloat) -> Void
    var onMotionSettled: (CGFloat) -> Void

    func makeUIView(context: Context) -> SheetEdgeHeightReaderView {
        let view = SheetEdgeHeightReaderView()
        view.onHeightChange = onHeightChange
        view.onMotionSettled = onMotionSettled
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: SheetEdgeHeightReaderView, context: Context) {
        uiView.onHeightChange = onHeightChange
        uiView.onMotionSettled = onMotionSettled
    }
}

final class SheetEdgeHeightReaderView: UIView {
    var onHeightChange: ((CGFloat) -> Void)?
    var onMotionSettled: ((CGFloat) -> Void)?
    private var lastReported: CGFloat = -1
    private var displayLink: CADisplayLink?
    private var stableFrameCount = 0
    private weak var cachedPresentedView: UIView?
    private static let stableFramesBeforePause = 8

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout changes mean the sheet may be moving again.
        stableFrameCount = 0
        startDisplayLinkIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        cachedPresentedView = nil
        if window != nil {
            stableFrameCount = 0
            startDisplayLinkIfNeeded()
            report()
        } else {
            stopDisplayLink()
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        // Sample while the card moves. Pause after stable frames to avoid
        // burning main-thread time while the sheet is idle.
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayLink() {
        report()
    }

    private func report() {
        guard window != nil else { return }

        let sheetFrame: CGRect
        if let presented = presentedSheetView() {
            sheetFrame = currentScreenFrame(of: presented)
        } else {
            guard bounds.height > 1 else { return }
            sheetFrame = convert(bounds, to: nil)
        }

        guard sheetFrame.height > 1 || sheetFrame.minY > 0 else { return }
        let screenHeight = window?.screen.bounds.height ?? UIScreen.main.bounds.height
        let heightFromBottom = max(0, screenHeight - sheetFrame.minY)
        guard heightFromBottom > 1 else { return }

        if abs(heightFromBottom - lastReported) < 0.25 {
            stableFrameCount += 1
            if stableFrameCount >= Self.stableFramesBeforePause {
                onMotionSettled?(heightFromBottom)
                stopDisplayLink()
            }
            return
        }

        stableFrameCount = 0
        lastReported = heightFromBottom
        onHeightChange?(heightFromBottom)
    }

    /// UIKit changes the model frame during a held drag, then uses Core Animation
    /// presentation layers for the release-to-detent animation. Reading only
    /// `UIView.frame` makes followers pause until that animation commits.
    private func currentScreenFrame(of presentedView: UIView) -> CGRect {
        if let window,
           let presentationLayer = presentedView.layer.presentation() {
            let windowLayer = window.layer.presentation() ?? window.layer
            let frameInWindow = presentationLayer.convert(
                presentationLayer.bounds,
                to: windowLayer
            )
            return window.convert(frameInWindow, to: nil)
        }

        if let container = presentedView.superview {
            return container.convert(presentedView.frame, to: nil)
        }
        return presentedView.convert(presentedView.bounds, to: nil)
    }

    private func presentedSheetView() -> UIView? {
        if let cachedPresentedView, cachedPresentedView.window != nil {
            return cachedPresentedView
        }
        guard let viewController = nearestViewController() else { return nil }
        cachedPresentedView = viewController.view
        return viewController.view
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

// MARK: - Collapsed content reveal

/// Applies opacity/offset for collapsed-sheet content reveal.
/// Only attached when the sheet is collapsed-like, so expanded lists do not
/// observe live height during normal drag.
struct SheetCollapsedRevealModifier: ViewModifier {
    @ObservedObject var geometry: SheetGeometryModel

    private let revealHeight: CGFloat = 140
    private let revealRange: CGFloat = 36

    private var progress: CGFloat {
        guard geometry.liveHeight > 1 else { return 0 }
        let raw = (geometry.liveHeight - revealHeight) / revealRange
        return min(max(raw, 0), 1)
    }

    func body(content: Content) -> some View {
        let p = progress
        content
            .opacity(p)
            .offset(y: (1 - p) * 10)
            .allowsHitTesting(p > 0.05)
            .accessibilityHidden(p <= 0.05)
    }
}

extension View {
    @ViewBuilder
    func sheetCollapsedReveal(
        geometry: SheetGeometryModel,
        isCollapsedLike: Bool,
        forceRevealed: Bool = false
    ) -> some View {
        // Skip observation entirely when fully revealed — critical for device drag FPS.
        if forceRevealed || !isCollapsedLike {
            self
        } else {
            modifier(SheetCollapsedRevealModifier(geometry: geometry))
        }
    }
}

import SwiftUI
import UIKit

struct FeatureHintsOverlay: View {
    @EnvironmentObject private var featureHintsController: FeatureHintsController

    var body: some View {
        GeometryReader { proxy in
            if let step = featureHintsController.activeStep {
                let targetFrame = featureHintsController.frame(for: step.target)

                ZStack {
                    if let targetFrame {
                        highlightedOverlay(
                            step: step,
                            highlightFrame: targetFrame,
                            containerSize: proxy.size
                        )
                    } else {
                        // Dim + card without highlight (e.g. while settings sheet is opening)
                        Color.black.opacity(0.42)
                        centeredCard(step: step, containerSize: proxy.size)
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: step.id)
                .animation(.easeInOut(duration: 0.25), value: targetFrame != nil)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(featureHintsController.isPresenting)
    }

    // MARK: - Highlighted overlay

    @ViewBuilder
    private func highlightedOverlay(
        step: FeatureHintStep,
        highlightFrame: CGRect,
        containerSize: CGSize
    ) -> some View {
        let insetFrame = paddedHighlightFrame(highlightFrame, for: step.target, in: containerSize)
        let cornerRadius = highlightCornerRadius(for: step.target)

        // Dim with cutout
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black.opacity(0.42))
            )
            context.blendMode = .destinationOut
            context.fill(
                Path(roundedRect: insetFrame,
                     cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
                     style: .continuous),
                with: .color(.white)
            )
        }
        .compositingGroup()

        // Highlight border
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .frame(width: insetFrame.width, height: insetFrame.height)
            .position(x: insetFrame.midX, y: insetFrame.midY)
            .shadow(color: Color.accentColor.opacity(0.16), radius: 8)

        // Tooltip card
        card(step: step, targetFrame: insetFrame, containerSize: containerSize)
    }

    // MARK: - Highlight frame

    private func paddedHighlightFrame(_ frame: CGRect, for target: FeatureHintTarget, in containerSize: CGSize) -> CGRect {
        let horizontalInset: CGFloat = frame.width > containerSize.width * 0.7 ? 8 : 10
        let verticalInset: CGFloat = 8
        let verticalOffset: CGFloat = {
            switch target {
            case .merchantSearch: return 6
            case .merchantAlerts: return 8
            case .communityToggle: return 0
            }
        }()
        let horizontalOffset: CGFloat = 0
        var expanded = frame.insetBy(dx: -horizontalInset, dy: -verticalInset)
            .offsetBy(dx: horizontalOffset, dy: verticalOffset)

        // Center wide highlights horizontally on screen
        if expanded.width > containerSize.width * 0.7 {
            expanded.origin.x = (containerSize.width - expanded.width) / 2
        }

        return CGRect(
            x: max(expanded.minX, 8),
            y: max(expanded.minY, 8),
            width: min(expanded.width, containerSize.width - 16),
            height: min(expanded.height, containerSize.height - 16)
        )
    }

    private func highlightCornerRadius(for target: FeatureHintTarget) -> CGFloat {
        switch target {
        case .communityToggle:
            return 20
        case .merchantSearch, .merchantAlerts:
            return 22
        }
    }

    // MARK: - Tooltip cards

    /// Card positioned relative to a highlighted target frame.
    private func card(step: FeatureHintStep, targetFrame: CGRect, containerSize: CGSize) -> some View {
        let horizontalPadding: CGFloat = 18
        let bubbleWidth = min(containerSize.width - horizontalPadding * 2, 300)
        let bubbleHeight = estimatedBubbleHeight(for: step, width: bubbleWidth)
        let safeInsets = screenSafeAreaInsets
        let gap: CGFloat = 20

        let bubbleY = bubbleYPosition(
            for: step.preferredCardPlacement,
            targetFrame: targetFrame,
            bubbleHeight: bubbleHeight,
            containerHeight: containerSize.height,
            safeTop: safeInsets.top + 8,
            safeBottom: safeInsets.bottom + 8,
            gap: gap
        )

        let bubbleX = min(
            max(targetFrame.midX, bubbleWidth / 2 + horizontalPadding),
            containerSize.width - bubbleWidth / 2 - horizontalPadding
        )

        return cardContent(step: step, width: bubbleWidth)
            .position(x: bubbleX, y: bubbleY)
    }

    /// Card centered on screen (used when target frame is not yet available).
    private func centeredCard(step: FeatureHintStep, containerSize: CGSize) -> some View {
        let horizontalPadding: CGFloat = 18
        let bubbleWidth = min(containerSize.width - horizontalPadding * 2, 300)

        return cardContent(step: step, width: bubbleWidth)
            .position(x: containerSize.width / 2, y: containerSize.height / 2)
    }

    /// Shared card content used by both positioned and centered variants.
    private func cardContent(step: FeatureHintStep, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tip \(featureHintsController.currentStepIndex + 1) of \(featureHintsController.activeCampaign?.steps.count ?? 0)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(step.title)
                .font(.headline)

            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Skip all") {
                    featureHintsController.skip()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button(featureHintsController.primaryButtonTitle) {
                    featureHintsController.advance()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 8)
    }

    // MARK: - Positioning

    private func bubbleYPosition(
        for placement: FeatureHintCardPlacement,
        targetFrame: CGRect,
        bubbleHeight: CGFloat,
        containerHeight: CGFloat,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        gap: CGFloat
    ) -> CGFloat {
        let aboveY = targetFrame.minY - gap - bubbleHeight / 2
        let belowY = targetFrame.maxY + gap + bubbleHeight / 2
        let minY = safeTop + bubbleHeight / 2
        let maxY = containerHeight - safeBottom - bubbleHeight / 2

        let preferredY: CGFloat
        switch placement {
        case .above:
            preferredY = aboveY >= minY ? aboveY : belowY
        case .below:
            preferredY = belowY <= maxY ? belowY : aboveY
        case .automatic:
            let hasRoomBelow = belowY <= maxY
            preferredY = hasRoomBelow ? belowY : aboveY
        }

        return min(max(preferredY, minY), maxY)
    }

    private var screenSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    private func estimatedBubbleHeight(for step: FeatureHintStep, width: CGFloat) -> CGFloat {
        let titleHeight: CGFloat = 28
        let metaHeight: CGFloat = 18
        let controlsHeight: CGFloat = 44
        let paddingHeight: CGFloat = 80

        let messageRect = NSString(string: step.message).boundingRect(
            with: CGSize(width: width - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)],
            context: nil
        )

        return ceil(messageRect.height) + titleHeight + metaHeight + controlsHeight + paddingHeight
    }
}

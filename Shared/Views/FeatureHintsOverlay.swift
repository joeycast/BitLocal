import SwiftUI
import UIKit

struct FeatureHintsOverlay: View {
    @Environment(FeatureHintsController.self) private var featureHintsController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let step = featureHintsController.activeStep {
                let targetFrame = featureHintsController.frame(for: step.target)
                let safeFrame = proxy.frame(in: .global)
                let safeInsets = proxy.safeAreaInsets
                let fullSize = CGSize(
                    width: proxy.size.width + safeInsets.leading + safeInsets.trailing,
                    height: proxy.size.height + safeInsets.top + safeInsets.bottom
                )

                ZStack {
                    if let targetFrame {
                        highlightedOverlay(
                            step: step,
                            highlightFrame: targetFrame,
                            fullContainerSize: fullSize,
                            safeContainerSize: proxy.size,
                            safeOrigin: safeFrame.origin
                        )
                    } else {
                        // Dim + card without highlight (e.g. while settings sheet is opening)
                        Color.black.opacity(0.42)
                            .ignoresSafeArea()
                        centeredCard(step: step, containerSize: proxy.size)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .transition(.opacity)
                .animation(
                    BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion),
                    value: step.id
                )
                .animation(
                    BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion),
                    value: targetFrame != nil
                )
            }
        }
        .allowsHitTesting(featureHintsController.isPresenting)
    }

    // MARK: - Highlighted overlay

    @ViewBuilder
    private func highlightedOverlay(
        step: FeatureHintStep,
        highlightFrame: CGRect,
        fullContainerSize: CGSize,
        safeContainerSize: CGSize,
        safeOrigin: CGPoint
    ) -> some View {
        let insetFrame = paddedHighlightFrame(highlightFrame, for: step.target, in: fullContainerSize)
        let localInsetFrame = insetFrame.offsetBy(dx: -safeOrigin.x, dy: -safeOrigin.y)
        let cornerRadius = highlightCornerRadius(for: step.target)

        // Dim with cutout (decorative scrim only ignores safe area)
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
        .ignoresSafeArea()

        // Highlight border
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .frame(width: localInsetFrame.width, height: localInsetFrame.height)
            .position(x: localInsetFrame.midX, y: localInsetFrame.midY)
            .shadow(color: Color.accentColor.opacity(0.16), radius: 8)

        // Tooltip card
        card(step: step, targetFrame: localInsetFrame, containerSize: safeContainerSize)
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

    /// Card positioned relative to a highlighted target frame within safe area bounds.
    private func card(step: FeatureHintStep, targetFrame: CGRect, containerSize: CGSize) -> some View {
        let horizontalPadding: CGFloat = 18
        let availableWidth = max(containerSize.width - horizontalPadding * 2, 200)
        let bubbleWidth = min(availableWidth, 300)
        let bubbleHeight = estimatedBubbleHeight(for: step, width: bubbleWidth)
        let gap: CGFloat = 20

        let bubbleY = bubbleYPosition(
            for: step.preferredCardPlacement,
            targetFrame: targetFrame,
            bubbleHeight: bubbleHeight,
            containerHeight: containerSize.height,
            safeTop: 8,
            safeBottom: 8,
            gap: gap
        )

        let minCenterX = horizontalPadding + bubbleWidth / 2
        let maxCenterX = max(minCenterX, containerSize.width - horizontalPadding - bubbleWidth / 2)
        let bubbleX = min(max(targetFrame.midX, minCenterX), maxCenterX)

        return cardContent(step: step, width: bubbleWidth)
            .position(x: bubbleX, y: bubbleY)
    }

    /// Card centered within the safe horizontal area (used when target frame is not yet available).
    private func centeredCard(step: FeatureHintStep, containerSize: CGSize) -> some View {
        let horizontalPadding: CGFloat = 18
        let availableWidth = max(containerSize.width - horizontalPadding * 2, 200)
        let bubbleWidth = min(availableWidth, 300)

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
                Button("Skip all", action: featureHintsController.skip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .contentShape(.rect)

                Spacer(minLength: 0)

                Button(featureHintsController.primaryButtonTitle, action: featureHintsController.advance)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .frame(minHeight: 44)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.05))
        }
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

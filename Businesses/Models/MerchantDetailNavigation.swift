import CoreGraphics
import Foundation

enum MerchantSequenceStepDirection: Equatable, Sendable {
    case previous
    case next
}

/// Pure, ordered sequence navigation state for stepping between adjacent merchants
/// in `BusinessDetailView` without accumulating redundant `NavigationStack` entries.
struct MerchantDetailSequenceNavigator: Equatable, Sendable {
    let orderedIDs: [String]
    let currentID: String

    init(orderedIDs: [String], currentID: String) {
        self.orderedIDs = Self.sanitizedSequence(from: orderedIDs)
        self.currentID = currentID
    }

    static func sanitizedSequence(from ids: [String]) -> [String] {
        var seen = Set<String>()
        seen.reserveCapacity(ids.count)
        var deduplicated: [String] = []
        deduplicated.reserveCapacity(ids.count)
        for id in ids where !id.isEmpty {
            if seen.insert(id).inserted {
                deduplicated.append(id)
            }
        }
        return deduplicated
    }

    var currentIndex: Int? {
        orderedIDs.firstIndex(of: currentID)
    }

    var totalCount: Int {
        orderedIDs.count
    }

    var previousID: String? {
        guard let index = currentIndex, index > 0 else { return nil }
        return orderedIDs[index - 1]
    }

    var nextID: String? {
        guard let index = currentIndex, index + 1 < orderedIDs.count else { return nil }
        return orderedIDs[index + 1]
    }

    var canStepPrevious: Bool {
        previousID != nil
    }

    var canStepNext: Bool {
        nextID != nil
    }

    var hasNeighbors: Bool {
        canStepPrevious || canStepNext
    }

    var positionLabel: String? {
        guard let index = currentIndex, totalCount > 1 else { return nil }
        return String(
            localized: "\(index + 1) of \(totalCount)",
            comment: "Current position within a merchant browsing list, e.g. 2 of 12"
        )
    }

    func targetID(for direction: MerchantSequenceStepDirection) -> String? {
        switch direction {
        case .previous:
            return previousID
        case .next:
            return nextID
        }
    }
}

/// Evaluates horizontal swipe gestures on `BusinessDetailView` while protecting
/// `NavigationStack`'s leading-edge interactive pop gesture and vertical scrolling.
enum MerchantDetailSwipeResolver {
    static let leadingEdgeGuardWidth: CGFloat = 44
    static let minimumHorizontalDistance: CGFloat = 24
    static let horizontalDominanceRatio: CGFloat = 1.5
    static let predictedCommitThreshold: CGFloat = 72
    static let directCommitThreshold: CGFloat = 88

    static func resolveSwipeDirection(
        startX: CGFloat,
        containerWidth: CGFloat,
        translation: CGSize,
        predictedEndTranslation: CGSize,
        isRightToLeft: Bool
    ) -> MerchantSequenceStepDirection? {
        guard containerWidth > 0 else { return nil }

        // Preserve system NavigationStack edge-swipe back gesture in both LTR and RTL.
        let distanceFromLeadingEdge = isRightToLeft ? (containerWidth - startX) : startX
        guard distanceFromLeadingEdge >= leadingEdgeGuardWidth else {
            return nil
        }

        let absWidth = abs(translation.width)
        let absHeight = abs(translation.height)
        guard absWidth >= minimumHorizontalDistance else {
            return nil
        }
        guard absWidth > absHeight * horizontalDominanceRatio else {
            return nil
        }

        let absPredictedWidth = abs(predictedEndTranslation.width)
        guard absPredictedWidth >= predictedCommitThreshold || absWidth >= directCommitThreshold else {
            return nil
        }

        let swipedLeft = translation.width < 0
        if isRightToLeft {
            return swipedLeft ? .previous : .next
        } else {
            return swipedLeft ? .next : .previous
        }
    }
}

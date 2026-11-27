import CoreGraphics
import SwiftUI
import Testing
@testable import bitlocal

@Suite(.tags(.routing))
struct MerchantDetailNavigationTests {

    @Test("Sequence navigator resolves previous and next neighbors in the middle of a list")
    func middleItemHasBothNeighbors() {
        let nav = MerchantDetailSequenceNavigator(
            orderedIDs: ["a", "b", "c"],
            currentID: "b"
        )

        #expect(nav.currentIndex == 1)
        #expect(nav.totalCount == 3)
        #expect(nav.previousID == "a")
        #expect(nav.nextID == "c")
        #expect(nav.canStepPrevious)
        #expect(nav.canStepNext)
        #expect(nav.hasNeighbors)
        #expect(nav.targetID(for: .previous) == "a")
        #expect(nav.targetID(for: .next) == "c")
        #expect(nav.positionLabel == "2 of 3")
    }

    @Test("Sequence navigator respects list boundaries and deduplicates repeated IDs")
    func boundariesAndDeduplication() {
        let first = MerchantDetailSequenceNavigator(
            orderedIDs: ["a", "b", "a", "", "c", "b"],
            currentID: "a"
        )
        #expect(first.orderedIDs == ["a", "b", "c"])
        #expect(first.previousID == nil)
        #expect(first.nextID == "b")
        #expect(!first.canStepPrevious)
        #expect(first.canStepNext)

        let last = MerchantDetailSequenceNavigator(
            orderedIDs: ["a", "b", "c"],
            currentID: "c"
        )
        #expect(last.previousID == "b")
        #expect(last.nextID == nil)
        #expect(last.canStepPrevious)
        #expect(!last.canStepNext)

        let single = MerchantDetailSequenceNavigator(orderedIDs: ["only"], currentID: "only")
        #expect(!single.hasNeighbors)
        #expect(single.positionLabel == nil)

        let missing = MerchantDetailSequenceNavigator(orderedIDs: ["a", "b"], currentID: "z")
        #expect(missing.currentIndex == nil)
        #expect(!missing.hasNeighbors)
        #expect(missing.positionLabel == nil)
    }

    @Test("Horizontal swipe resolves next/previous in LTR and flips cleanly in RTL")
    func horizontalSwipeDirectionLTRAndRTL() {
        let ltrNext = MerchantDetailSwipeResolver.resolveSwipeDirection(
            startX: 200,
            containerWidth: 390,
            translation: CGSize(width: -95, height: 10),
            predictedEndTranslation: CGSize(width: -140, height: 12),
            isRightToLeft: false
        )
        #expect(ltrNext == .next)

        let ltrPrev = MerchantDetailSwipeResolver.resolveSwipeDirection(
            startX: 160,
            containerWidth: 390,
            translation: CGSize(width: 95, height: -8),
            predictedEndTranslation: CGSize(width: 140, height: -10),
            isRightToLeft: false
        )
        #expect(ltrPrev == .previous)

        let rtlNext = MerchantDetailSwipeResolver.resolveSwipeDirection(
            startX: 180,
            containerWidth: 390,
            translation: CGSize(width: 95, height: 5),
            predictedEndTranslation: CGSize(width: 120, height: 5),
            isRightToLeft: true
        )
        #expect(rtlNext == .next)

        let rtlPrev = MerchantDetailSwipeResolver.resolveSwipeDirection(
            startX: 180,
            containerWidth: 390,
            translation: CGSize(width: -95, height: 5),
            predictedEndTranslation: CGSize(width: -120, height: 5),
            isRightToLeft: true
        )
        #expect(rtlPrev == .previous)
    }

    @Test("Swipe resolver protects leading-edge NavigationStack back gesture and vertical scrolling")
    func swipeProtectsEdgeBackAndVerticalScroll() {
        // Leading-edge swipe in LTR must not steal NavigationStack interactive pop.
        let ltrEdgeSwipe = MerchantDetailSwipeResolver.resolveSwipeDirection(
            startX: 20,
            containerWidth: 390,
            translation: CGSize(width: 120, height: 0),
            predictedEndTranslation: CGSize(width: 180, height: 0),
            isRightToLeft: false
        )
        #expect(ltrEdgeSwipe == nil)

        // Leading-edge swipe in RTL (near right edge) must not steal interactive pop.
        let rtlEdgeSwipe = MerchantDetailSwipeResolver.resolveSwipeDirection(
            startX: 370,
            containerWidth: 390,
            translation: CGSize(width: -120, height: 0),
            predictedEndTranslation: CGSize(width: -180, height: 0),
            isRightToLeft: true
        )
        #expect(rtlEdgeSwipe == nil)

        // Diagonal / vertical scrolling must not trigger merchant stepping.
        let verticalScroll = MerchantDetailSwipeResolver.resolveSwipeDirection(
            startX: 200,
            containerWidth: 390,
            translation: CGSize(width: -50, height: -60),
            predictedEndTranslation: CGSize(width: -100, height: -140),
            isRightToLeft: false
        )
        #expect(verticalScroll == nil)

        // Short horizontal nudge below commit threshold must not step.
        let shortNudge = MerchantDetailSwipeResolver.resolveSwipeDirection(
            startX: 200,
            containerWidth: 390,
            translation: CGSize(width: -32, height: 2),
            predictedEndTranslation: CGSize(width: -48, height: 2),
            isRightToLeft: false
        )
        #expect(shortNudge == nil)
    }

    @Test("Full-screen detent helper distinguishes .large from leading-side floating detent")
    func fullScreenDetentDetection() {
        #expect(BottomSheetDetents.isFullScreen(.large))
        #expect(!BottomSheetDetents.isFullScreen(BottomSheetDetents.expandedLeading))
        #expect(!BottomSheetDetents.isFullScreen(BottomSheetDetents.standard))
        #expect(!BottomSheetDetents.isFullScreen(BottomSheetDetents.collapsed))
        #expect(!BottomSheetDetents.isFullScreen(nil))
    }
}

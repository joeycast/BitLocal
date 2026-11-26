import XCTest
@testable import bitlocal

@MainActor
final class BitLocalAppIntentsAndRoutingTests: XCTestCase {
    func testAppIntentRouterPostsAndConsumesPendingActionOnce() {
        let router = BitLocalAppIntentRouter()
        XCTAssertNil(router.pendingAction)
        XCTAssertNil(router.consumePendingAction())

        router.post(.openMerchants(filter: .lightning, searchQuery: "coffee"))
        XCTAssertEqual(router.pendingAction, .openMerchants(filter: .lightning, searchQuery: "coffee"))

        let consumed = router.consumePendingAction()
        XCTAssertEqual(consumed, .openMerchants(filter: .lightning, searchQuery: "coffee"))
        XCTAssertNil(router.pendingAction)
        XCTAssertNil(router.consumePendingAction())
    }

    func testMerchantQuickFilterMetadataIsComplete() {
        for filter in MerchantQuickFilter.allCases {
            XCTAssertFalse(filter.id.isEmpty)
            XCTAssertFalse(filter.displayTitle.isEmpty)
            XCTAssertFalse(filter.systemImage.isEmpty)
            XCTAssertNotNil(MerchantQuickFilter.caseDisplayRepresentations[filter])
        }
    }

    func testBitLocalNavigationRouteExposesElementAndStableID() {
        let element = makeElement(id: "place-99")

        let placeRoute = BitLocalNavigationRoute.place(element)
        XCTAssertEqual(placeRoute.element?.id, "place-99")
        XCTAssertEqual(placeRoute.id, "place-99")

        let commentsRoute = BitLocalNavigationRoute.placeComments(element)
        XCTAssertEqual(commentsRoute.element?.id, "place-99")
        XCTAssertEqual(commentsRoute.id, "place-99")
        XCTAssertNotEqual(placeRoute, commentsRoute)

        let eventsRoute = BitLocalNavigationRoute.allEvents
        XCTAssertNil(eventsRoute.element)
        XCTAssertEqual(eventsRoute.id, "all-events")
    }

    private func makeElement(id: String) -> Element {
        let osmJSON = OsmJSON(
            changeset: nil,
            id: nil,
            lat: 36.16,
            lon: -86.78,
            tags: nil,
            timestamp: nil,
            type: .node,
            uid: nil,
            user: nil,
            version: nil,
            bounds: nil,
            geometry: nil,
            nodes: nil,
            members: nil
        )
        return Element(
            id: id,
            osmJSON: osmJSON,
            tags: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
    }
}

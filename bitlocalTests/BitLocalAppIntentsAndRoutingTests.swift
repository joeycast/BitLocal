import Testing
@testable import bitlocal

@MainActor
@Suite(.tags(.routing))
struct BitLocalAppIntentsAndRoutingTests {
    @Test func appIntentRouterPostsAndConsumesPendingActionOnce() {
        let router = BitLocalAppIntentRouter()
        #expect(router.pendingAction == nil)
        #expect(router.consumePendingAction() == nil)

        router.post(.openMerchants(filter: .lightning, searchQuery: "coffee"))
        #expect(router.pendingAction == .openMerchants(filter: .lightning, searchQuery: "coffee"))

        let consumed = router.consumePendingAction()
        #expect(consumed == .openMerchants(filter: .lightning, searchQuery: "coffee"))
        #expect(router.pendingAction == nil)
        #expect(router.consumePendingAction() == nil)
    }

    @Test(arguments: MerchantQuickFilter.allCases)
    func merchantQuickFilterMetadataIsComplete(filter: MerchantQuickFilter) {
        #expect(filter.id.isEmpty == false)
        #expect(filter.displayTitle.isEmpty == false)
        #expect(filter.systemImage.isEmpty == false)
        #expect(MerchantQuickFilter.caseDisplayRepresentations[filter] != nil)
    }

    @Test func bitLocalNavigationRouteExposesElementAndStableID() {
        let element = makeElement(id: "place-99")

        let placeRoute = BitLocalNavigationRoute.place(element)
        #expect(placeRoute.element?.id == "place-99")
        #expect(placeRoute.id == "place-99")

        let commentsRoute = BitLocalNavigationRoute.placeComments(element)
        #expect(commentsRoute.element?.id == "place-99")
        #expect(commentsRoute.id == "place-99")
        #expect(placeRoute != commentsRoute)

        let eventsRoute = BitLocalNavigationRoute.allEvents
        #expect(eventsRoute.element == nil)
        #expect(eventsRoute.id == "all-events")
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

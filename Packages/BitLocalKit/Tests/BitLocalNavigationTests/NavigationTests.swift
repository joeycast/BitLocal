import CoreGraphics
import Foundation
import Testing
@testable import BitLocalNavigation
import BitLocalDomain

@Suite("PostureResolver")
struct PostureResolverTests {
    func resolve(_ w: CGFloat, _ h: CGFloat, _ hc: SizeClass?, divisions: [Division] = []) -> LayoutPosture {
        PostureResolver.resolve(GeometrySnapshot(size: CGSize(width: w, height: h), horizontal: hc, vertical: .regular, divisions: divisions))
    }

    @Test func phones() {
        #expect(resolve(393, 852, .compact) == .compact(shortHeight: false))
        #expect(resolve(375, 667, .compact) == .compact(shortHeight: true))
    }

    @Test func duoOuterDisplay() {
        #expect(resolve(466, 678, .compact) == .compact(shortHeight: true))
        #expect(resolve(678, 466, .compact) == .compactLandscape)
    }

    @Test func iPadWidths() {
        #expect(resolve(820, 1180, .regular) == .regular)
        #expect(resolve(1180, 820, .regular) == .expanded)
        #expect(resolve(1366, 1024, .regular) == .expanded)
        #expect(resolve(320, 1180, .compact) == .compact(shortHeight: false))
    }

    @Test func missingSizeClassIsCompact() {
        #expect(resolve(900, 900, nil) == .compact(shortHeight: false))
    }

    @Test func duoInnerDisplayWithoutFoldInfo() {
        #expect(resolve(951, 669, .regular) == .regular)
        #expect(resolve(669, 951, .regular) == .regular)
    }

    @Test func folds() {
        let vertical = Division(frame: CGRect(x: 470, y: 0, width: 12, height: 669), isActive: false)
        #expect(resolve(951, 669, .regular, divisions: [vertical]) == .foldColumns(divisionFrame: vertical.frame, isActive: false))
        let horizontal = Division(frame: CGRect(x: 0, y: 470, width: 669, height: 12), isActive: true)
        #expect(resolve(669, 951, .regular, divisions: [horizontal]) == .foldStack(divisionFrame: horizontal.frame, isActive: true))
    }

    @Test func zeroOrSquareDivisionsAreIgnored() {
        let empty = Division(frame: .zero, isActive: false)
        #expect(resolve(951, 669, .regular, divisions: [empty]) == .regular)
        let square = Division(frame: CGRect(x: 0, y: 0, width: 20, height: 20), isActive: true)
        #expect(resolve(951, 669, .regular, divisions: [square]) == .regular)
    }
}

@MainActor
@Suite("AppNavigation")
struct AppNavigationTests {
    let phone = GeometrySnapshot(size: CGSize(width: 393, height: 852), horizontal: .compact, vertical: .regular)
    let iPadPortrait = GeometrySnapshot(size: CGSize(width: 820, height: 1180), horizontal: .regular, vertical: .regular)
    let iPadLandscape = GeometrySnapshot(size: CGSize(width: 1180, height: 820), horizontal: .regular, vertical: .regular)
    let duoUnfolded = GeometrySnapshot(size: CGSize(width: 951, height: 669), horizontal: .regular, vertical: .regular,
                                       divisions: [Division(frame: CGRect(x: 470, y: 0, width: 12, height: 669), isActive: false)])
    let shop = Selection.merchant(MerchantID(1))

    @Test func compactSelectionShowsCardAndDeselectRestoresDetent() {
        let nav = AppNavigation()
        nav.updateGeometry(phone)
        nav.sheetDetent = .peek
        let effects = nav.select(shop, source: .map)
        #expect(nav.sheetDetent == .card)
        #expect(!effects.revealOnMap)
        #expect(nav.path == [.merchant(MerchantID(1))])
        nav.select(nil, source: .map)
        #expect(nav.sheetDetent == .peek)
        #expect(nav.path.isEmpty)
    }

    @Test func listSelectionAtFullStaysFullAndReveals() {
        let nav = AppNavigation()
        nav.updateGeometry(phone)
        nav.sheetDetent = .full
        let effects = nav.select(shop, source: .list)
        #expect(nav.sheetDetent == .full)
        #expect(effects.revealOnMap)
        #expect(nav.pendingReveal == MerchantID(1))
    }

    @Test func regularPushesAndExpandedUsesInspector() {
        let nav = AppNavigation()
        nav.updateGeometry(iPadPortrait)
        nav.select(shop, source: .list)
        #expect(nav.path == [.merchant(MerchantID(1))])
        #expect(!nav.isInspectorPresented)

        nav.updateGeometry(iPadLandscape)
        #expect(nav.posture == .expanded)
        #expect(nav.isInspectorPresented)
        #expect(nav.path.isEmpty)

        nav.updateGeometry(iPadPortrait)
        #expect(nav.path == [.merchant(MerchantID(1))])
    }

    @Test func foldRoundTripKeepsSelectionAndDetent() {
        let nav = AppNavigation()
        nav.updateGeometry(phone)
        nav.select(shop, source: .map)
        #expect(nav.sheetDetent == .card)

        nav.updateGeometry(duoUnfolded)
        #expect(nav.posture.isFold)
        #expect(nav.selection == shop)
        #expect(nav.path == [.merchant(MerchantID(1))])

        nav.updateGeometry(phone)
        #expect(nav.posture.usesSheet)
        #expect(nav.selection == shop)
        #expect(nav.sheetDetent == .card)
    }

    @Test func resizingBackToCompactWithoutSelectionRestoresLastDetent() {
        let nav = AppNavigation()
        nav.updateGeometry(phone)
        nav.sheetDetent = .full
        nav.updateGeometry(iPadLandscape)
        nav.updateGeometry(phone)
        #expect(nav.sheetDetent == .full)
    }

    @Test func deeperPathReturnsAtFull() {
        let nav = AppNavigation()
        nav.updateGeometry(iPadPortrait)
        nav.select(shop, source: .list)
        nav.path.append(.allReviews(MerchantID(1)))
        nav.updateGeometry(phone)
        #expect(nav.sheetDetent == .full)
    }

    @Test func restorationRoundTrip() throws {
        let nav = AppNavigation()
        nav.updateGeometry(phone)
        nav.select(shop, source: .list)
        nav.searchQuery = "coffee"
        let data = try JSONEncoder().encode(nav.restorationState)
        let restored = AppNavigation()
        restored.restore(try JSONDecoder().decode(NavigationState.self, from: data))
        #expect(restored.restorationState == nav.restorationState)
    }
}

@Suite("MapFraming")
struct MapFramingTests {
    @Test func focusStaysAtUnobscuredCenter() {
        let focus = Coordinate(latitude: 36, longitude: -86)
        // Map 400x800, sheet covers the bottom 300pt: unobscured center is 250pt from the top, 150pt above map center.
        let camera = MapFraming.camera(keeping: focus, metersPerPoint: 10, mapSize: CGSize(width: 400, height: 800),
                                       unobscured: CGRect(x: 0, y: 0, width: 400, height: 500))
        // Map center must sit 150pt (1,500 m) south of the focus.
        #expect(camera.center.latitude < focus.latitude)
        #expect(abs((focus.latitude - camera.center.latitude) * 111_320 - 1_500) < 1)
        #expect(abs(camera.center.longitude - focus.longitude) < 1e-9)
        #expect(camera.metersPerPoint == 10)
    }

    @Test func sidebarShiftsCenterWest() {
        let focus = Coordinate(latitude: 0, longitude: 0)
        let camera = MapFraming.camera(keeping: focus, metersPerPoint: 1, mapSize: CGSize(width: 1000, height: 800),
                                       unobscured: CGRect(x: 400, y: 0, width: 600, height: 800))
        #expect(camera.center.longitude < 0)
    }

    @Test func standAloneZoomNeverZoomsOut() {
        #expect(MapFraming.standAloneMetersPerPoint(neighborDistance: 960, current: 100) == 1.5)
        #expect(MapFraming.standAloneMetersPerPoint(neighborDistance: 96, current: 100) == 1)
        #expect(MapFraming.standAloneMetersPerPoint(neighborDistance: 960, current: 0.5) == 0.5)
        #expect(MapFraming.standAloneMetersPerPoint(neighborDistance: 0, current: 100) == 0.1)
    }
}

@Suite("Card paging")
struct CardPagingTests {
    @Test func claimsOnlyMostlyHorizontalDrags() {
        #expect(!CardPaging.claims(dx: 8, dy: 0))
        #expect(CardPaging.claims(dx: -12, dy: 3))
        #expect(!CardPaging.claims(dx: 12, dy: 10))
    }

    @Test func stepsByDistanceOrFlick() {
        #expect(CardPaging.step(translation: -100, velocity: 0, width: 360) == 1)
        #expect(CardPaging.step(translation: 100, velocity: 0, width: 360) == -1)
        #expect(CardPaging.step(translation: -30, velocity: -200, width: 360) == 1)
        #expect(CardPaging.step(translation: -30, velocity: -50, width: 360) == 0)
    }

    @Test func neighbors() {
        let order = [1, 2, 3]
        #expect(CardPaging.neighbor(of: 2, in: order, step: 1) == 3)
        #expect(CardPaging.neighbor(of: 1, in: order, step: -1) == nil)
        #expect(CardPaging.neighbor(of: 9, in: order, step: 1) == nil)
    }

    @Test func rubberBandsAtTheEnds() {
        #expect(CardPaging.offset(for: -100, hasPrevious: true, hasNext: false) == -30)
        #expect(CardPaging.offset(for: -100, hasPrevious: false, hasNext: true) == -100)
        #expect(CardPaging.offset(for: 50, hasPrevious: false, hasNext: true) == 15)
    }
}

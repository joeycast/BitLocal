//
//  CompactLayoutView.swift
//  bitlocal
//
//  Redesign phase 3: the compact layout (every iPhone, iPad Slide Over and
//  narrow Split View, Duo folded). Full-bleed map, map controls pinned
//  top-trailing inside the safe area, and one system sheet with three named
//  detents. No header bar, and no live sheet-height tracking: the map's
//  bottom inset comes from the *target* detent (ui-redesign.md 4.3).
//

import SwiftUI
import MapKit
import BitLocalDesign
import BitLocalNavigation

struct CompactLayoutView: View {
    @ObservedObject var viewModel: ContentViewModel
    var visibleElements: [Element]
    @Binding var showingSettings: Bool
    var selectedMapTypeBinding: Binding<MKMapType>
    /// Distance from the window top that something occludes beyond the safe area
    /// (the folded Duo's camera and status strip). Zero on other devices.
    var topOcclusion: CGFloat = 0

    @Environment(AppNavigation.self) private var navigation
    @EnvironmentObject private var appearanceManager: AppearanceManager
    @EnvironmentObject private var releaseNotesController: ReleaseNotesController
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var settingsSheetDetent: PresentationDetent = .medium

    private var shouldPresentBottomSheet: Bool {
        didCompleteOnboarding &&
        viewModel.isReadyForPostOnboardingPresentation &&
        !releaseNotesController.isPresenting
    }

    var body: some View {
        GeometryReader { geometry in
            let containerHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let cardHeight = SheetDetentHeights.card(containerHeight: containerHeight)
            let fullDetent = SheetDetentHeights.full(
                containerHeight: containerHeight,
                safeTop: geometry.safeAreaInsets.top,
                topOcclusion: topOcclusion
            )

            ZStack {
                MapView(
                    topPadding: geometry.safeAreaInsets.top,
                    bottomPadding: viewModel.bottomPadding,
                    mapType: selectedMapTypeBinding.wrappedValue,
                    storeRenderToken: StoreMap.shared.renderToken
                )
                .ignoresSafeArea()
                .onAppear {
                    viewModel.locationManager.startUpdatingLocation()
                }
            }
            // No top bar any more: the map's top inset is just the safe area.
            .onChange(of: geometry.safeAreaInsets.top, initial: true) { _, top in
                if viewModel.topPadding != top { viewModel.topPadding = top }
            }
            // Attribution sits just above the sheet's target detent and never chases a drag.
            .overlay(alignment: .bottomLeading) {
                OpenStreetMapAttributionView()
                    .padding(.leading, Spacing.screenEdge)
                    .padding(.bottom, shouldPresentBottomSheet
                             ? SheetDetentHeights.mapInset(for: navigation.sheetDetent, cardHeight: cardHeight) - geometry.safeAreaInsets.bottom + 4
                             : 8)
                    .opacity(navigation.sheetDetent == .full ? 0 : 1)
            }
            // Controls are pinned top-trailing inside the safe area (clear of the Duo
            // outer camera strip) and fade past the card detent. Opacity only, no movement.
            .overlay(alignment: .topTrailing) {
                MapButtonsView(
                    viewModel: viewModel,
                    selectedMapTypeBinding: selectedMapTypeBinding,
                    userLocation: viewModel.userLocation,
                    isIPad: false
                )
                .padding(.top, Spacing.xs)
                .padding(.trailing, Spacing.screenEdge)
                .opacity(navigation.sheetDetent == .full || showingSettings ? 0 : 1)
                .allowsHitTesting(navigation.sheetDetent != .full && !showingSettings)
                .animation(Motion.fade, value: navigation.sheetDetent)
            }
            .sheet(isPresented: .constant(shouldPresentBottomSheet)) {
                BottomSheetContentView(
                    visibleElements: visibleElements,
                    currentDetent: detentBinding(cardHeight: cardHeight, fullDetent: fullDetent),
                    onSettings: { showingSettings = true }
                )
                .id("\(appearanceManager.appearance.rawValue)-\(systemColorScheme)")
                .environmentObject(viewModel)
                .preferredColorScheme(effectiveColorScheme)
                .presentationDetents(
                    [BottomSheetDetents.collapsed, .height(cardHeight), fullDetent],
                    selection: detentBinding(cardHeight: cardHeight, fullDetent: fullDetent)
                )
                // Hidden: the header draws its own grabber (see `SheetGrabber`, DECISIONS 89).
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(cardHeight)))
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        SettingsView(
                            selectedMapType: selectedMapTypeBinding,
                            currentDetent: $settingsSheetDetent
                        )
                        .environmentObject(viewModel)
                        .environmentObject(MerchantAlertsManager.shared)
                    }
                    .id("settings-sheet-\(appearanceManager.appearance.rawValue)-\(systemColorScheme)")
                    .preferredColorScheme(effectiveColorScheme)
                    .presentationDetents([.medium, .large], selection: $settingsSheetDetent)
                    .settingsSheetBackground()
                }
            }
            .onAppear {
                applyMapInset(cardHeight: cardHeight)
            }
            .onChange(of: navigation.sheetDetent) { _, _ in
                applyMapInset(cardHeight: cardHeight)
            }
            .onChange(of: cardHeight) { _, newHeight in
                applyMapInset(cardHeight: newHeight)
            }
            .onChange(of: shouldPresentBottomSheet) { _, _ in
                applyMapInset(cardHeight: cardHeight)
            }
            .onChange(of: showingSettings) { _, isShowing in
                if isShowing { settingsSheetDetent = .medium }
            }
            .ignoresSafeArea(.keyboard)
        }
    }

    /// Maps the navigation model's named detent to the system sheet's detents.
    private func detentBinding(cardHeight: CGFloat, fullDetent: PresentationDetent) -> Binding<PresentationDetent> {
        Binding(
            get: {
                switch navigation.sheetDetent {
                case .peek: BottomSheetDetents.collapsed
                case .card: .height(cardHeight)
                case .full: fullDetent
                }
            },
            set: { detent in
                let named: SheetDetent
                if detent == BottomSheetDetents.collapsed {
                    named = .peek
                } else if detent == fullDetent || detent == .large {
                    named = .full
                } else {
                    named = .card
                }
                if navigation.sheetDetent != named { navigation.sheetDetent = named }
            }
        )
    }

    /// The map's bottom inset follows the target detent, set once per change.
    private func applyMapInset(cardHeight: CGFloat) {
        let inset = shouldPresentBottomSheet
            ? SheetDetentHeights.mapInset(for: navigation.sheetDetent, cardHeight: cardHeight)
            : 0
        viewModel.applyTargetSheetHeight(inset)
    }

    private var effectiveColorScheme: ColorScheme? {
        switch appearanceManager.appearance {
        case .system: systemColorScheme
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Heights for the three compact detents (ui-redesign.md 4.3).
enum SheetDetentHeights {
    /// `card` is a fixed share of the window, clamped to 260–380 pt, until the
    /// merchant card can be measured (phase 5).
    static func card(containerHeight: CGFloat) -> CGFloat {
        let range = LayoutMetrics.cardDetentRange
        return min(max((containerHeight * 0.36).rounded(), range.lowerBound), range.upperBound)
    }

    /// The full detent is the system `.large`, unless something occludes the top of
    /// the window below the safe area (the folded Duo's camera and status strip sat on
    /// the search field). Then the sheet stops 8 pt under it.
    static func full(containerHeight: CGFloat, safeTop: CGFloat, topOcclusion: CGFloat) -> PresentationDetent {
        guard topOcclusion > safeTop else { return .large }
        return .height(max(containerHeight - topOcclusion - 8, LayoutMetrics.cardDetentRange.upperBound))
    }

    /// The map inset for a detent. At `full` the map is hidden, so keep the card inset
    /// and avoid a camera jump when the sheet comes back down.
    static func mapInset(for detent: SheetDetent, cardHeight: CGFloat) -> CGFloat {
        switch detent {
        case .peek: BottomSheetDetents.collapsedHeight
        case .card, .full: cardHeight
        }
    }
}

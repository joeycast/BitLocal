//
//  IPhoneLayoutView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import SwiftUI
import MapKit
import Combine
import Foundation // for Debug logging
import UIKit

struct IPhoneLayoutView: View {
    @ObservedObject var viewModel: ContentViewModel
    var elements: [Element]?
    var visibleElements: [Element]
    @Binding var showingSettings: Bool
    @Binding var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>

    var body: some View {
        NavigationStack {
            IPhoneLayoutContent(
                viewModel: viewModel,
                elements: elements,
                visibleElements: visibleElements,
                showingSettings: $showingSettings,
                headerHeight: $headerHeight,
                selectedMapTypeBinding: selectedMapTypeBinding
            )
        }
    }
}

private struct IPhoneLayoutContent: View {
    @ObservedObject var viewModel: ContentViewModel
    var elements: [Element]?
    var visibleElements: [Element]
    @Binding var showingSettings: Bool
    @Binding var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>

    // Add this to track onboarding state
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }
    @EnvironmentObject var appearanceManager: AppearanceManager
    @EnvironmentObject private var releaseNotesController: ReleaseNotesController
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.isVerticalToolbarActive) private var isVerticalToolbarActive

    private var appearance: Appearance { appearanceManager.appearance }
    @State private var recenterController = MapLocationRecenterController()
    @State private var bottomSheetDetent: PresentationDetent = .fraction(0.37)
    @State private var settingsSheetDetent: PresentationDetent = .large
    @State private var hasLiveSheetMeasurement = false
    @State private var hasAcceptedDefaultLiveMeasurement = false
    @State private var pendingLaunchOutlier: CGFloat?
    private let collapsedSheetDetent: PresentationDetent = BottomSheetDetents.collapsed
    private let defaultSheetDetent: PresentationDetent = .fraction(0.37)
    private var shouldPresentBottomSheet: Bool {
        didCompleteOnboarding &&
        viewModel.isReadyForPostOnboardingPresentation &&
        !releaseNotesController.isPresenting
    }

    private var usesNativeHorizontalBar: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    private var showsLegacyHeader: Bool {
        !isVerticalToolbarActive && !usesNativeHorizontalBar
    }

    var body: some View {
        GeometryReader { geometry in
            let elements = self.elements
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let leadingSheetWidth = geometry.leadingCollapsibleSheetWidth(
                horizontalSizeClass: horizontalSizeClass,
                layoutDirection: layoutDirection
            )
            let isLeadingSheet = leadingSheetWidth != nil

            ZStack {
                if let elements = elements {
                    MapView(
                        elements: elements,
                        topPadding: headerHeight,
                        bottomPadding: viewModel.bottomPadding,
                        mapType: selectedMapType
                    )
                    .ignoresSafeArea()
                    .onAppear {
                        viewModel.locationManager.startUpdatingLocation()
                    }
                    // Attribution observes settled padding only (via this layout's
                    // onChange of bottomPadding / detent), not live drag height.
                    .overlay(alignment: .bottomLeading) {
                        OpenStreetMapAttributionView()
                            .padding(
                                .bottom,
                                isLeadingSheet
                                    ? max(geometry.safeAreaInsets.bottom, 8)
                                    : attributionBottomInset(for: fullHeight) + 6
                            )
                            .padding(
                                .leading,
                                isLeadingSheet
                                    ? (leadingSheetWidth ?? 0) + 28
                                    : geometry.safeAreaInsets.leading + 16
                            )
                    }
                }
                if showsLegacyHeader {
                    VStack {
                        IPhoneHeaderView(
                            screenWidth: geometry.size.width,
                            viewModel: viewModel,
                            showingSettings: $showingSettings
                        )
                        Spacer()
                    }
                }
            }
            // Map buttons live in a child that observes `sheetGeometry` only, so
            // continuous drag height does not rebuild MapView / this ZStack.
            // On iPhone Duo poses with a vertical side bar, they move into `.toolbar`.
            .overlay(alignment: shouldPresentBottomSheet ? .bottomTrailing : .topTrailing) {
                if !isVerticalToolbarActive {
                    IPhoneMapButtonsChrome(
                        viewModel: viewModel,
                        sheetGeometry: viewModel.sheetGeometry,
                        selectedMapTypeBinding: selectedMapTypeBinding,
                        mapHeight: geometry.size.height,
                        safeTopInset: geometry.safeAreaInsets.top,
                        safeBottomInset: geometry.safeAreaInsets.bottom,
                        headerHeight: headerHeight,
                        shouldPresentBottomSheet: shouldPresentBottomSheet,
                        showingSettings: showingSettings,
                        useMonochromeIcons: horizontalSizeClass == .regular
                    )
                }
            }
            .toolbar {
                if isVerticalToolbarActive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("settings_label_accessibility", systemImage: "gearshape")
                                .foregroundStyle(.primary)
                                .id("settings-\(effectiveColorScheme == .dark)")
                        }
                        .tint(.primary)
                    }

                    MapControlToolbarContent(
                        viewModel: viewModel,
                        selectedMapTypeBinding: selectedMapTypeBinding,
                        recenterController: recenterController,
                        placement: .topBarTrailing,
                        colorScheme: effectiveColorScheme
                    )
                } else if usesNativeHorizontalBar {
                    ToolbarItem(placement: .principal) {
                        Text("bitlocal")
                            .font(.custom("Fredoka-Medium", size: 28, relativeTo: .title))
                            .foregroundStyle(.accent)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("settings_label_accessibility", systemImage: "gearshape")
                                .foregroundStyle(.primary)
                                .id("settings-h-\(effectiveColorScheme == .dark)")
                        }
                        .tint(.primary)
                    }
                }
            }
            .toolbarVisibility(showsLegacyHeader ? .hidden : .visible, for: .navigationBar)
            .locationRecenterAlerts(controller: recenterController)
            .toolbarColorScheme(effectiveColorScheme, for: .navigationBar)
            .modifier(LegacyHiddenToolbarBackgroundModifier())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .sheet(isPresented: .constant(shouldPresentBottomSheet), onDismiss: {
                Debug.log("Bottom sheet dismissed")
            }) {
                let topDetent: PresentationDetent = isLeadingSheet
                    ? BottomSheetDetents.expandedLeading
                    : .large
                BottomSheetContentView(
                    visibleElements: visibleElements,
                    currentDetent: $bottomSheetDetent,
                    preferredLeadingWidth: leadingSheetWidth
                )
                    .environmentObject(viewModel)
                    .preferredColorScheme(effectiveColorScheme)  // To respect appearance
                    .presentationDetents([
                        collapsedSheetDetent,
                        defaultSheetDetent,
                        .medium,
                        topDetent
                    ], selection: $bottomSheetDetent)
                    .presentationSizing(
                        AdaptiveLeadingSheetSizing(
                            maxWidth: leadingSheetWidth,
                            maxHeight: fullHeight
                        )
                    )
                    .adaptiveSheetPlacement(leading: isLeadingSheet)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(true)
                    .presentationBackgroundInteraction(.enabled)
                    .sheet(isPresented: $showingSettings) {
                        NavigationStack {
                            SettingsView(
                                selectedMapType: selectedMapTypeBinding,
                                currentDetent: $settingsSheetDetent
                            )
                            .environmentObject(viewModel)
                            .environmentObject(MerchantAlertsManager.shared)
                        }
                        .preferredColorScheme(effectiveColorScheme)
                        .presentationDetents([.medium, .large], selection: $settingsSheetDetent)
                        .settingsSheetBackground()
                    }
            }
            .onAppear {
                syncTopPadding(safeTopInset: geometry.safeAreaInsets.top)
                viewModel.leadingSheetInset = leadingSheetWidth ?? 0
                hasLiveSheetMeasurement = false
                hasAcceptedDefaultLiveMeasurement = false
                pendingLaunchOutlier = nil
                if shouldPresentBottomSheet {
                    let settledHeight = estimatedBottomInsetForDetent(mapHeight: fullHeight)
                    viewModel.reportSheetDetentSettled(estimatedHeight: settledHeight)
                }
                let inset = attributionBottomInset(for: fullHeight)
                Debug.logMap(
                    "Attribution launch: detent=\(bottomSheetDetent), " +
                    "hasLiveSheetMeasurement=\(hasLiveSheetMeasurement), " +
                    "bottomPadding=\(viewModel.bottomPadding), mapHeight=\(fullHeight), inset=\(inset)"
                )
            }
            .onDisappear {
                viewModel.leadingSheetInset = 0
            }
            .onChange(of: leadingSheetWidth) { _, newWidth in
                viewModel.leadingSheetInset = newWidth ?? 0
                if newWidth != nil, bottomSheetDetent == .large {
                    bottomSheetDetent = BottomSheetDetents.expandedLeading
                } else if newWidth == nil, bottomSheetDetent == BottomSheetDetents.expandedLeading {
                    bottomSheetDetent = .large
                }
            }
            .onChange(of: isVerticalToolbarActive) { _, _ in
                syncTopPadding(safeTopInset: geometry.safeAreaInsets.top)
            }
            .onChange(of: geometry.safeAreaInsets.top) { _, newTop in
                syncTopPadding(safeTopInset: newTop)
            }
            .onChange(of: shouldPresentBottomSheet) { _, isPresented in
                if isPresented {
                    let settledHeight = estimatedBottomInsetForDetent(mapHeight: fullHeight)
                    viewModel.reportSheetDetentSettled(estimatedHeight: settledHeight)
                }
                Debug.logTiming(
                    "onboarding",
                    "bottom sheet eligibility changed -> presented=\(isPresented), ready=\(viewModel.isReadyForPostOnboardingPresentation), onboarding=\(didCompleteOnboarding), visibleElements=\(visibleElements.count), selected=\(viewModel.selectedElement?.id ?? "nil")"
                )
            }
            .onChange(of: visibleElements.count) { _, count in
                guard shouldPresentBottomSheet else { return }
                Debug.logTiming(
                    "map",
                    "bottom sheet visibleElements updated -> count=\(count), detent=\(bottomSheetDetent)"
                )
            }
            .onChange(of: viewModel.bottomPadding) { _, newValue in
                if newValue > 1 {
                    let expected = estimatedBottomInsetForDetent(mapHeight: fullHeight)
                    let isDefaultDetent = isDefaultLikeDetent(bottomSheetDetent)
                    let isPlausibleAtDefault = abs(newValue - expected) <= 24

                    if isDefaultDetent && !hasAcceptedDefaultLiveMeasurement {
                        if isPlausibleAtDefault {
                            hasAcceptedDefaultLiveMeasurement = true
                            pendingLaunchOutlier = nil
                        } else if let previousOutlier = pendingLaunchOutlier,
                                  abs(newValue - previousOutlier) > 5 {
                            // The sheet is actively moving/settling; switch to live tracking.
                            hasAcceptedDefaultLiveMeasurement = true
                            pendingLaunchOutlier = nil
                        } else {
                            pendingLaunchOutlier = newValue
                            let inset = attributionBottomInset(for: fullHeight)
                            Debug.logMap(
                                "Attribution bottomPadding ignored (launch outlier): detent=\(bottomSheetDetent), " +
                                "bottomPadding=\(newValue), expected=\(expected), inset=\(inset)"
                            )
                            return
                        }
                    }
                    hasLiveSheetMeasurement = true
                }
                let inset = attributionBottomInset(for: fullHeight)
                Debug.logMap(
                    "Attribution bottomPadding changed: detent=\(bottomSheetDetent), " +
                    "hasLiveSheetMeasurement=\(hasLiveSheetMeasurement), " +
                    "bottomPadding=\(newValue), mapHeight=\(fullHeight), inset=\(inset)"
                )
            }
            .onChange(of: bottomSheetDetent) { _, newDetent in
                if !isDefaultLikeDetent(newDetent) {
                    // Once the user leaves the default/large viewport, always trust live geometry.
                    hasAcceptedDefaultLiveMeasurement = true
                }
                // The selection changes at the start of UIKit's snap animation.
                // Defer map padding publication until the measured card stops moving.
                let settledHeight = estimatedBottomInsetForDetent(mapHeight: fullHeight)
                viewModel.prepareForSheetDetentTransition(estimatedHeight: settledHeight)
                let inset = attributionBottomInset(for: fullHeight)
                Debug.logMap(
                    "Attribution detent changed: detent=\(newDetent), " +
                    "hasLiveSheetMeasurement=\(hasLiveSheetMeasurement), " +
                    "bottomPadding=\(viewModel.bottomPadding), mapHeight=\(fullHeight), inset=\(inset)"
                )
            }
            .onChange(of: geometry.size) { _, _ in
                guard shouldPresentBottomSheet, fullHeight > 1 else { return }
                hasLiveSheetMeasurement = false
                hasAcceptedDefaultLiveMeasurement = false
                pendingLaunchOutlier = nil
                let settledHeight = estimatedBottomInsetForDetent(mapHeight: fullHeight)
                viewModel.reportSheetDetentSettled(estimatedHeight: settledHeight)
            }
            .onChange(of: showingSettings) { _, isShowing in
                if isShowing {
                    settingsSheetDetent = .large
                }
            }
            .ignoresSafeArea(.keyboard)
            .animation(.easeInOut(duration: 0.25), value: appearance)
            .animation(.easeInOut(duration: 0.25), value: systemColorScheme)
        }
    }

    private func syncTopPadding(safeTopInset: CGFloat) {
        guard !showsLegacyHeader else { return }
        let resolvedTop = isVerticalToolbarActive ? 0 : safeTopInset
        if headerHeight != resolvedTop {
            headerHeight = resolvedTop
        }
        if viewModel.topPadding != resolvedTop {
            viewModel.topPadding = resolvedTop
        }
    }

    private var effectiveColorScheme: ColorScheme? {
        switch appearance {
        case .system:
            return systemColorScheme  // Explicitly use the current system scheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func attributionBottomInset(for mapHeight: CGFloat) -> CGFloat {
        let estimatedInset = estimatedBottomInsetForDetent(mapHeight: mapHeight)
        if isDefaultLikeDetent(bottomSheetDetent), !hasAcceptedDefaultLiveMeasurement {
            return estimatedInset
        }
        // Settled geometry only — continuous drag tracking lives on map buttons chrome.
        if hasLiveSheetMeasurement, viewModel.bottomPadding > 1 {
            return min(max(viewModel.bottomPadding, 0), mapHeight - 1)
        }
        return estimatedInset
    }

    private func estimatedBottomInsetForDetent(mapHeight: CGFloat) -> CGFloat {
        if isCollapsedLikeDetent(bottomSheetDetent) {
            return BottomSheetDetents.collapsedHeight
        }
        if isDefaultLikeDetent(bottomSheetDetent) {
            return mapHeight * 0.37
        }
        if isMediumDetent(bottomSheetDetent) {
            return mapHeight * 0.50
        }
        // Keep large detent aligned with default viewport behavior.
        return mapHeight * 0.37
    }

    private func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
    }

    private func isCollapsedLikeDetent(_ detent: PresentationDetent) -> Bool {
        detent == BottomSheetDetents.collapsed || detentIdentifier(detent).contains("fraction 0.11")
    }

    private func isDefaultLikeDetent(_ detent: PresentationDetent) -> Bool {
        if detent == defaultSheetDetent || detent == BottomSheetDetents.expandedLeading {
            return true
        }
        let id = detentIdentifier(detent)
        return id.contains("fraction 0.3") || id.contains("large") || id.contains("fraction 0.92")
    }

    private func isMediumDetent(_ detent: PresentationDetent) -> Bool {
        detentIdentifier(detent).contains("medium")
    }
}

/// Map control chrome that stays at a fixed SwiftUI anchor. Continuous sheet
/// motion is applied directly to its UIKit host view below.
private struct IPhoneMapButtonsChrome: View {
    @ObservedObject var viewModel: ContentViewModel
    /// Not observed — continuous height arrives via Combine subject.
    var sheetGeometry: SheetGeometryModel
    var selectedMapTypeBinding: Binding<MKMapType>
    var mapHeight: CGFloat
    var safeTopInset: CGFloat
    var safeBottomInset: CGFloat
    var headerHeight: CGFloat
    var shouldPresentBottomSheet: Bool
    var showingSettings: Bool
    var useMonochromeIcons: Bool = false

    private let mapButtonsPillHeight: CGFloat = 132
    /// Gap between the top of the sheet card and the bottom of the control pill.
    private let sheetClearance: CGFloat = 12

    var body: some View {
        IPhoneMapButtonsUIKitHost(
            viewModel: viewModel,
            sheetGeometry: sheetGeometry,
            selectedMapTypeBinding: selectedMapTypeBinding,
            fallbackSheetHeight: fallbackSheetHeight,
            safeBottomInset: safeBottomInset,
            maximumBottomOffset: maxMapButtonsBottomInset,
            sheetClearance: sheetClearance,
            tracksSheet: shouldPresentBottomSheet,
            useMonochromeIcons: useMonochromeIcons
        )
        .fixedSize()
        .padding(.trailing, 18)
        .padding(.top, shouldPresentBottomSheet ? 0 : mapOverlayTopOffset)
        .opacity(showingSettings ? 0 : 1)
        .allowsHitTesting(!showingSettings)
        .transaction { $0.animation = nil }
        .animation(.easeInOut(duration: 0.2), value: showingSettings)
    }

    private var fallbackSheetHeight: CGFloat {
        viewModel.bottomPadding > 1 ? viewModel.bottomPadding : mapHeight * 0.30
    }

    private var maxMapButtonsBottomInset: CGFloat {
        max(0, mapHeight - mapOverlayTopOffset - mapButtonsPillHeight)
    }

    private var mapOverlayTopOffset: CGFloat {
        let isNotch = safeTopInset >= 40
        if isNotch {
            return max(headerHeight - 28, 8)
        } else {
            return max(headerHeight - 5, 8)
        }
    }
}

/// Hosts the SwiftUI button pill in UIKit so display-link updates only change a
/// layer transform. This avoids a SwiftUI state write and layout pass per frame.
private struct IPhoneMapButtonsUIKitHost: UIViewControllerRepresentable {
    var viewModel: ContentViewModel
    var sheetGeometry: SheetGeometryModel
    var selectedMapTypeBinding: Binding<MKMapType>
    var fallbackSheetHeight: CGFloat
    var safeBottomInset: CGFloat
    var maximumBottomOffset: CGFloat
    var sheetClearance: CGFloat
    var tracksSheet: Bool
    var useMonochromeIcons: Bool = false

    func makeUIViewController(context: Context) -> SheetTrackingMapButtonsController {
        let controller = SheetTrackingMapButtonsController(rootView: hostedContent)
        controller.update(
            rootView: hostedContent,
            geometry: sheetGeometry,
            fallbackSheetHeight: fallbackSheetHeight,
            safeBottomInset: safeBottomInset,
            maximumBottomOffset: maximumBottomOffset,
            sheetClearance: sheetClearance,
            tracksSheet: tracksSheet
        )
        return controller
    }

    func updateUIViewController(
        _ uiViewController: SheetTrackingMapButtonsController,
        context: Context
    ) {
        uiViewController.update(
            rootView: hostedContent,
            geometry: sheetGeometry,
            fallbackSheetHeight: fallbackSheetHeight,
            safeBottomInset: safeBottomInset,
            maximumBottomOffset: maximumBottomOffset,
            sheetClearance: sheetClearance,
            tracksSheet: tracksSheet
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: SheetTrackingMapButtonsController,
        context: Context
    ) -> CGSize? {
        uiViewController.hostingController.sizeThatFits(
            in: CGSize(
                width: proposal.width ?? 10_000,
                height: proposal.height ?? 10_000
            )
        )
    }

    static func dismantleUIViewController(
        _ uiViewController: SheetTrackingMapButtonsController,
        coordinator: Void
    ) {
        uiViewController.cancel()
    }

    private var hostedContent: MapButtonsView {
        MapButtonsView(
            viewModel: viewModel,
            selectedMapTypeBinding: selectedMapTypeBinding,
            useMonochromeIcons: useMonochromeIcons
        )
    }
}

@MainActor
private final class SheetTrackingMapButtonsController: UIViewController {
    let hostingController: UIHostingController<MapButtonsView>

    private var cancellable: AnyCancellable?
    private weak var geometry: SheetGeometryModel?
    private var fallbackSheetHeight: CGFloat = 0
    private var safeBottomInset: CGFloat = 0
    private var maximumBottomOffset: CGFloat = 0
    private var sheetClearance: CGFloat = 0
    private var tracksSheet = false

    init(rootView: MapButtonsView) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = SheetTrackingHitContainerView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        (view as? SheetTrackingHitContainerView)?.transformedView = hostingController.view
    }

    func update(
        rootView: MapButtonsView,
        geometry: SheetGeometryModel,
        fallbackSheetHeight: CGFloat,
        safeBottomInset: CGFloat,
        maximumBottomOffset: CGFloat,
        sheetClearance: CGFloat,
        tracksSheet: Bool
    ) {
        loadViewIfNeeded()
        hostingController.rootView = rootView
        self.fallbackSheetHeight = fallbackSheetHeight
        self.safeBottomInset = safeBottomInset
        self.maximumBottomOffset = maximumBottomOffset
        self.sheetClearance = sheetClearance
        self.tracksSheet = tracksSheet

        if self.geometry !== geometry {
            cancellable?.cancel()
            self.geometry = geometry
            cancellable = geometry.continuousHeightPublisher
                .sink { [weak self] height in
                    self?.applyTransform(for: height)
                }
        }

        applyTransform(for: geometry.continuousHeight)
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
    }

    private func applyTransform(for height: CGFloat) {
        let translationY: CGFloat
        if tracksSheet {
            let resolvedHeight = height > 1 ? height : fallbackSheetHeight
            let sheetInset = max(resolvedHeight - safeBottomInset, 0)
            let targetBottomOffset = min(
                max(sheetInset + sheetClearance, 0),
                maximumBottomOffset
            )
            translationY = -targetBottomOffset
        } else {
            translationY = 0
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostingController.view.transform = CGAffineTransform(
            translationX: 0,
            y: translationY
        )
        CATransaction.commit()
    }
}

private final class SheetTrackingHitContainerView: UIView {
    weak var transformedView: UIView?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        guard let transformedView else { return false }
        let transformedPoint = transformedView.convert(point, from: self)
        return transformedView.point(inside: transformedPoint, with: event)
    }
}

/// Only hides the legacy solid navigation bar background prior to iOS 26;
/// on iOS 26+, Liquid Glass manages bar chrome and adaptive contrast natively.
private struct LegacyHiddenToolbarBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
    }
}

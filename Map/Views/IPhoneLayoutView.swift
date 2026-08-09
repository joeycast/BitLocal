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
    @Binding var showingAbout: Bool
    @Binding var showingSettings: Bool
    @Binding var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>

    // Add this to track onboarding state
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }
    @EnvironmentObject var appearanceManager: AppearanceManager
    @EnvironmentObject private var releaseNotesController: ReleaseNotesController
    @Environment(\.colorScheme) private var systemColorScheme
    
    private var appearance: Appearance { appearanceManager.appearance }
    @State private var bottomSheetDetent: PresentationDetent = .fraction(0.3)
    @State private var settingsSheetDetent: PresentationDetent = .medium
    @State private var hasLiveSheetMeasurement = false
    @State private var hasAcceptedDefaultLiveMeasurement = false
    @State private var pendingLaunchOutlier: CGFloat?
    private let collapsedSheetDetent: PresentationDetent = BottomSheetDetents.collapsed
    private let defaultSheetDetent: PresentationDetent = .fraction(0.3)
    private var shouldPresentBottomSheet: Bool {
        didCompleteOnboarding &&
        viewModel.isReadyForPostOnboardingPresentation &&
        !releaseNotesController.isPresenting
    }

    var body: some View {
        GeometryReader { geometry in
            let elements = self.elements

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
                    .overlay(
                        OpenStreetMapAttributionView()
                            .padding(.bottom, attributionBottomInset(for: geometry.size.height) + 1)
                            .padding(.leading, 16),
                        alignment: .bottomLeading
                    )
                }
                VStack {
                    IPhoneHeaderView(
                        screenWidth: geometry.size.width,
                        viewModel: viewModel,
                        showingAbout: $showingAbout,
                        showingSettings: $showingSettings,
                        selectedMapTypeBinding: selectedMapTypeBinding
                        // Removed appearance and systemColorScheme parameters
                    )
                    Spacer()
                }
            }
            // Map buttons live in a child that observes `sheetGeometry` only, so
            // continuous drag height does not rebuild MapView / this ZStack.
            .overlay(alignment: shouldPresentBottomSheet ? .bottomTrailing : .topTrailing) {
                IPhoneMapButtonsChrome(
                    viewModel: viewModel,
                    sheetGeometry: viewModel.sheetGeometry,
                    selectedMapTypeBinding: selectedMapTypeBinding,
                    mapHeight: geometry.size.height,
                    safeTopInset: geometry.safeAreaInsets.top,
                    safeBottomInset: geometry.safeAreaInsets.bottom,
                    headerHeight: headerHeight,
                    shouldPresentBottomSheet: shouldPresentBottomSheet,
                    showingSettings: showingSettings
                )
            }
//            // Only show bottom sheet after onboarding is complete
//            .bottomSheet(
//                presentationDetents: [.fraction(0.3), .medium, .large],
//                isPresented: .constant(didCompleteOnboarding), // Changed this line
//                dragIndicator: .visible,
//                sheetCornerRadius: 20,
//                largestUndimmedIdentifier: .medium,
//                interactiveDisabled: true,
//                forcedColorScheme: nil, // Let the content handle its own color scheme
//                content: {
//                    BottomSheetContentView(visibleElements: visibleElements)
//                        .id("\(appearance.rawValue)-\(systemColorScheme)")
//                        .environmentObject(viewModel)
//                        .background(Color(UIColor.systemBackground))
//                        .preferredColorScheme(effectiveColorScheme)
//                        .environment(\.colorScheme, effectiveColorScheme ?? systemColorScheme)
//                        .sheet(isPresented: $showingAbout) {
//                            AboutView()
//                        }
//                },
//                onDismiss: {
//                    Debug.log("Bottom sheet dismissed")
//                }
//            )
            .sheet(isPresented: .constant(shouldPresentBottomSheet), onDismiss: {
                Debug.log("Bottom sheet dismissed")
            }) {
                BottomSheetContentView(
                    visibleElements: visibleElements,
                    currentDetent: $bottomSheetDetent
                )
                    .id("\(appearance.rawValue)-\(systemColorScheme)")
                    .environmentObject(viewModel)
                    .preferredColorScheme(effectiveColorScheme)  // To respect appearance
//                    .presentationBackground(Color(UIColor.systemBackground))  // Keeps background opaque, resolves based on the preferred scheme
                    .presentationDetents([
                        collapsedSheetDetent,
                        defaultSheetDetent,
                        .medium,
                        .large
                    ], selection: $bottomSheetDetent)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(true)
                    .presentationBackgroundInteraction(.enabled)
                    .sheet(isPresented: $showingAbout) {
                        AboutView()
                            .environmentObject(viewModel)
                    }
                    .sheet(isPresented: $showingSettings) {
                        NavigationStack {
                            SettingsView(
                                selectedMapType: selectedMapTypeBinding,
                                currentDetent: $settingsSheetDetent
                            )
                            .environmentObject(viewModel)
                            .environmentObject(MerchantAlertsManager.shared)
                        }
                        .id("settings-sheet-\(appearance.rawValue)-\(systemColorScheme)")
                        .preferredColorScheme(effectiveColorScheme)
                        .presentationDetents([.medium, .large], selection: $settingsSheetDetent)
                        .settingsSheetBackground()
                    }
            }
            .onAppear {
                hasLiveSheetMeasurement = false
                hasAcceptedDefaultLiveMeasurement = false
                pendingLaunchOutlier = nil
                if shouldPresentBottomSheet {
                    let settledHeight = estimatedBottomInsetForDetent(mapHeight: geometry.size.height)
                    viewModel.reportSheetDetentSettled(estimatedHeight: settledHeight)
                }
                let inset = attributionBottomInset(for: geometry.size.height)
                Debug.logMap(
                    "Attribution launch: detent=\(bottomSheetDetent), " +
                    "hasLiveSheetMeasurement=\(hasLiveSheetMeasurement), " +
                    "bottomPadding=\(viewModel.bottomPadding), mapHeight=\(geometry.size.height), inset=\(inset)"
                )
            }
            .onChange(of: shouldPresentBottomSheet) { _, isPresented in
                if isPresented {
                    let settledHeight = estimatedBottomInsetForDetent(mapHeight: geometry.size.height)
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
                    let expected = estimatedBottomInsetForDetent(mapHeight: geometry.size.height)
                    let isDefaultDetent = isDefaultLikeDetent(bottomSheetDetent)
                    let isPlausibleAtDefault = abs(newValue - expected) <= 8

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
                            let inset = attributionBottomInset(for: geometry.size.height)
                            Debug.logMap(
                                "Attribution bottomPadding ignored (launch outlier): detent=\(bottomSheetDetent), " +
                                "bottomPadding=\(newValue), expected=\(expected), inset=\(inset)"
                            )
                            return
                        }
                    }
                    hasLiveSheetMeasurement = true
                }
                let inset = attributionBottomInset(for: geometry.size.height)
                Debug.logMap(
                    "Attribution bottomPadding changed: detent=\(bottomSheetDetent), " +
                    "hasLiveSheetMeasurement=\(hasLiveSheetMeasurement), " +
                    "bottomPadding=\(newValue), mapHeight=\(geometry.size.height), inset=\(inset)"
                )
            }
            .onChange(of: bottomSheetDetent) { _, newDetent in
                if !isDefaultLikeDetent(newDetent) {
                    // Once the user leaves the default/large viewport, always trust live geometry.
                    hasAcceptedDefaultLiveMeasurement = true
                }
                // The selection changes at the start of UIKit's snap animation.
                // Defer map padding publication until the measured card stops moving.
                let settledHeight = estimatedBottomInsetForDetent(mapHeight: geometry.size.height)
                viewModel.prepareForSheetDetentTransition(estimatedHeight: settledHeight)
                let inset = attributionBottomInset(for: geometry.size.height)
                Debug.logMap(
                    "Attribution detent changed: detent=\(newDetent), " +
                    "hasLiveSheetMeasurement=\(hasLiveSheetMeasurement), " +
                    "bottomPadding=\(viewModel.bottomPadding), mapHeight=\(geometry.size.height), inset=\(inset)"
                )
            }
            .onChange(of: showingSettings) { _, isShowing in
                if isShowing {
                    settingsSheetDetent = .medium
                }
            }
            .ignoresSafeArea(.keyboard)
            .animation(.easeInOut(duration: 0.25), value: appearance)
            .animation(.easeInOut(duration: 0.25), value: systemColorScheme)
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

    private func mapOverlayTopOffset(for safeTopInset: CGFloat) -> CGFloat {
        let isNotch = safeTopInset >= 40
        if isNotch {
            return headerHeight - 28   // tune notch devices
        } else {
            return headerHeight - 5   // tune legacy/home-button devices
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
            return mapHeight * 0.30
        }
        if isMediumDetent(bottomSheetDetent) {
            return mapHeight * 0.50
        }
        // Keep large detent aligned with default viewport behavior.
        return mapHeight * 0.30
    }

    private func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
    }

    private func isCollapsedLikeDetent(_ detent: PresentationDetent) -> Bool {
        detent == BottomSheetDetents.collapsed || detentIdentifier(detent).contains("fraction 0.11")
    }

    private func isDefaultLikeDetent(_ detent: PresentationDetent) -> Bool {
        let id = detentIdentifier(detent)
        return id.contains("fraction 0.3") || id.contains("large")
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
            tracksSheet: shouldPresentBottomSheet
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
            return headerHeight - 28
        } else {
            return headerHeight - 5
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
            userLocation: viewModel.userLocation,
            isIPad: false
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

//
//  IPhoneLayoutView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import SwiftUI
import MapKit
import Foundation // for Debug logging

@available(iOS 17.0, *)
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
    @Environment(\.colorScheme) private var systemColorScheme
    
    private var appearance: Appearance { appearanceManager.appearance }
    @State private var bottomSheetDetent: PresentationDetent = .fraction(0.3)
    @State private var settingsSheetDetent: PresentationDetent = .medium
    private let collapsedSheetDetent: PresentationDetent = .fraction(0.11)
    private let defaultSheetDetent: PresentationDetent = .fraction(0.3)

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
            .overlay(
                MapButtonsView(
                    viewModel: viewModel,
                    selectedMapTypeBinding: selectedMapTypeBinding,
                    userLocation: viewModel.userLocation,
                    isIPad: false
                )
                .padding(.trailing, 18)
                .padding(.top, mapOverlayTopOffset(for: geometry.safeAreaInsets.top))
                .opacity(showingSettings ? 0 : 1)
                .allowsHitTesting(!showingSettings)
                .animation(.easeInOut(duration: 0.2), value: showingSettings),
                alignment: .topTrailing
            )
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
            .sheet(isPresented: .constant(didCompleteOnboarding), onDismiss: {
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
                    }
                    .sheet(isPresented: $showingSettings) {
                        NavigationStack {
                            SettingsView(
                                selectedMapType: selectedMapTypeBinding,
                                currentDetent: $settingsSheetDetent
                            )
                            .environmentObject(MerchantAlertsManager.shared)
                        }
                        .id("settings-sheet-\(appearance.rawValue)-\(systemColorScheme)")
                        .preferredColorScheme(effectiveColorScheme)
                        .presentationDetents([.medium, .large], selection: $settingsSheetDetent)
                        .settingsSheetBackground()
                    }
            }
            .onAppear {
                let inset = estimatedBottomInsetForDetent(mapHeight: geometry.size.height)
                viewModel.bottomPadding = inset
                Debug.logMap(
                    "Attribution launch: detent=\(bottomSheetDetent), " +
                    "bottomPadding=\(viewModel.bottomPadding), mapHeight=\(geometry.size.height), inset=\(inset)"
                )
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                viewModel.bottomPadding = estimatedBottomInsetForDetent(mapHeight: newHeight)
            }
            .onChange(of: bottomSheetDetent) { _, newDetent in
                let inset = estimatedBottomInsetForDetent(mapHeight: geometry.size.height)
                viewModel.bottomPadding = inset
                Debug.logMap(
                    "Attribution detent changed: detent=\(newDetent), " +
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
        estimatedBottomInsetForDetent(mapHeight: mapHeight)
    }

    private func estimatedBottomInsetForDetent(mapHeight: CGFloat) -> CGFloat {
        if isCollapsedLikeDetent(bottomSheetDetent) {
            return mapHeight * 0.11
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
        let id = detentIdentifier(detent)
        return id.contains("fraction 0.11")
    }

    private func isDefaultLikeDetent(_ detent: PresentationDetent) -> Bool {
        let id = detentIdentifier(detent)
        return id.contains("fraction 0.3") || id.contains("large")
    }

    private func isMediumDetent(_ detent: PresentationDetent) -> Bool {
        detentIdentifier(detent).contains("medium")
    }
}

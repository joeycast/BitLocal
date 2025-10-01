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
                            .padding(.bottom, geometry.size.height * 0.3 + 1)
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
                .padding(.trailing, 27)
                .padding(.bottom, geometry.size.height * 0.3 + 10),
                alignment: .bottomTrailing
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
                        .fraction(0.3),
                        .medium,
                        .large
                    ], selection: $bottomSheetDetent)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(true)
                    .presentationBackgroundInteraction(.enabled)
                    .sheet(isPresented: $showingAbout) {
                        AboutView()
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
}

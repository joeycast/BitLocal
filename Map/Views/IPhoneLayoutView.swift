//
//  IPhoneLayoutView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI
import MapKit

@available(iOS 17.0, *)
struct IPhoneLayoutView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Binding var elements: [Element]?
    @Binding var visibleElements: [Element]
    @Binding var showingAbout: Bool
    @Binding var showingSettings: Bool
    @Binding var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>


    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        GeometryReader { geometry in
            let elements = self.elements

            ZStack {
                if let elements = elements {
                    MapView(
                        elements: .constant(elements),
                        topPadding: headerHeight,
                        bottomPadding: viewModel.bottomPadding,
                        mapType: selectedMapType
                    )
                    .ignoresSafeArea()
                    .onAppear {
                        viewModel.locationManager.requestWhenInUseAuthorization()
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
            .bottomSheet(
                presentationDetents: [.fraction(0.3), .medium, .large],
                isPresented: .constant(true),
                dragIndicator: .visible,
                sheetCornerRadius: 20,
                largestUndimmedIdentifier: .medium,
                interactiveDisabled: true,
                forcedColorScheme: colorSchemeFor(appearance),
                content: {
                    BottomSheetContentView(visibleElements: $visibleElements)
                        .id(appearance)
                        .environmentObject(viewModel)
                        .preferredColorScheme(colorSchemeFor(appearance))
                },
                onDismiss: {
                    print("Bottom sheet dismissed")
                }
            )
            .ignoresSafeArea(.keyboard)
        }
    }

    private func colorSchemeFor(_ appearance: Appearance) -> ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

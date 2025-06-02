// NOTE: elements and visibleElements are intentionally passed as plain values (not bindings) to IPadLayoutView and IPhoneLayoutView.
// ContentView.swift

import SwiftUI
import MapKit
import CoreLocationUI
import Combine
import Foundation
import Foundation // for Debug logging

@available(iOS 17.0, *)
struct ContentView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var appearanceManager = AppearanceManager()

    @State public var showingAbout = false
    @State private var userLocation: CLLocation?
    @State private var cancellable: Cancellable?
    @State private var mapStoppedMovingCancellable: Cancellable?
    @State private var cancellableUserLocation: Cancellable?
    @State private var firstLocationUpdate: Bool = true
    @State private var headerHeight: CGFloat = 0
    @State private var showingSettings = false

    @AppStorage("selectedMapType") private var storedMapType: Int = 0
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    let apiManager = APIManager()

    var selectedMapTypeBinding: Binding<MKMapType> {
        Binding<MKMapType>(
            get: { MKMapType.from(int: storedMapType) },
            set: { storedMapType = $0.intValue }
        )
    }
    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            if screenWidth > 768 || screenHeight > 1024 {
                IPadLayoutView(
                    viewModel: viewModel,
                    elements: viewModel.allElements,
                    visibleElements: viewModel.visibleElements,
                    showingAbout: $showingAbout,
                    showingSettings: $showingSettings,
                    headerHeight: $headerHeight,
                    selectedMapTypeBinding: selectedMapTypeBinding
                )
                .environmentObject(appearanceManager)
            } else {
                IPhoneLayoutView(
                    viewModel: viewModel,
                    elements: viewModel.allElements,
                    visibleElements: viewModel.visibleElements,
                    showingAbout: $showingAbout,
                    showingSettings: $showingSettings,
                    headerHeight: $headerHeight,
                    selectedMapTypeBinding: selectedMapTypeBinding
                )
                .environmentObject(appearanceManager)
            }
        }
        .onPreferenceChange(HeaderHeightKey.self) { value in
            self.headerHeight = value
            viewModel.topPadding = value
            Debug.log("Header Height reported: \(value)")
        }
        .onAppear {
            Debug.log("ContentView.onAppear called")

            cancellableUserLocation = viewModel.userLocationSubject.sink { updatedUserLocation in
                userLocation = updatedUserLocation
            }
            mapStoppedMovingCancellable = viewModel.mapStoppedMovingSubject.sink(receiveValue: {})
        }
        .preferredColorScheme(colorSchemeFor(appearanceManager.appearance))
    }

    // Helper function to map Appearance -> ColorScheme?
    private func colorSchemeFor(_ appearance: Appearance) -> ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

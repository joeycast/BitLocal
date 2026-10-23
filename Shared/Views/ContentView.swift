// NOTE: elements and visibleElements are intentionally passed as plain values (not bindings) to IPadLayoutView and IPhoneLayoutView.
// ContentView.swift

import SwiftUI
import MapKit
import CoreLocationUI
import Combine
import Foundation
import Foundation // for Debug logging

struct ContentView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    @EnvironmentObject private var featureHintsController: FeatureHintsController
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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

    var selectedMapTypeBinding: Binding<MKMapType> {
        Binding<MKMapType>(
            get: { MKMapType.from(int: storedMapType) },
            set: { storedMapType = $0.intValue }
        )
    }
    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    /// Pick the shell from size classes, not the device idiom. iOS 27 runs
    /// phone-idiom apps in regular-width windows (iPhone Duo unfolded, iPhone
    /// apps on iPad), so idiom no longer says how much room we have.
    /// Compact height (large iPhones in landscape) keeps the phone shell.
    private var usesIPadLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass != .compact
    }

    var body: some View {
        Group {
            if usesIPadLayout {
                IPadLayoutView(
                    viewModel: viewModel,
                    elements: viewModel.mapElementsForCurrentDisplay,
                    visibleElements: viewModel.listElementsForCurrentDisplay,
                    showingAbout: $showingAbout,
                    showingSettings: $showingSettings,
                    headerHeight: $headerHeight,
                    selectedMapTypeBinding: selectedMapTypeBinding
                )
                .environmentObject(appearanceManager)
            } else {
                IPhoneLayoutView(
                    viewModel: viewModel,
                    elements: viewModel.mapElementsForCurrentDisplay,
                    visibleElements: viewModel.listElementsForCurrentDisplay,
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
            viewModel.usesSplitLayout = usesIPadLayout

            cancellableUserLocation = viewModel.userLocationSubject.sink { updatedUserLocation in
                userLocation = updatedUserLocation
            }
            mapStoppedMovingCancellable = viewModel.mapStoppedMovingSubject.sink(receiveValue: {})
        }
        .onChange(of: usesIPadLayout) { _, usesSplit in
            // Folding/unfolding swaps shells live; drop the phone header and
            // sheet insets so the split view's map isn't padded by stale values.
            viewModel.usesSplitLayout = usesSplit
            if usesSplit {
                headerHeight = 0
                viewModel.topPadding = 0
                viewModel.bottomPadding = 0
            }
        }
        .onChange(of: featureHintsController.activeTarget) { _, target in
            if target == .merchantAlerts {
                showingSettings = true
            }
        }
        .onChange(of: featureHintsController.isPresenting) { _, isPresenting in
            if !isPresenting, showingSettings {
                showingSettings = false
            }
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

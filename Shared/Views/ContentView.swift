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
    @Environment(\.isVerticalToolbarActive) private var isVerticalToolbarActive
    @StateObject private var appearanceManager = AppearanceManager()

    @State public var showingAbout = false
    @State private var userLocation: CLLocation?
    @State private var cancellable: Cancellable?
    @State private var mapStoppedMovingCancellable: Cancellable?
    @State private var cancellableUserLocation: Cancellable?
    @State private var firstLocationUpdate: Bool = true
    @State private var headerHeight: CGFloat = 0
    @State private var showingSettings = false
    @State private var containerSize: CGSize = .zero

    @AppStorage("selectedMapType") private var storedMapType: Int = 0
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    var selectedMapTypeBinding: Binding<MKMapType> {
        Binding<MKMapType>(
            get: { MKMapType.from(int: storedMapType) },
            set: { storedMapType = $0.intValue }
        )
    }
    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    /// Size-class + container-geometry shell selection (never `userInterfaceIdiom`):
    /// iPhone Duo keeps the collapsible sheet shell across all poses (pinning the
    /// sheet to the leading side in unfolded landscape), while iPad uses split view.
    private var layoutMode: AppLayoutMode {
        AppLayoutMode.resolve(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            containerSize: containerSize,
            isVerticalToolbarActive: isVerticalToolbarActive
        )
    }

    var body: some View {
        ZStack {
            if layoutMode == .splitSidebar {
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
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            if newSize != containerSize {
                containerSize = newSize
            }
        }
        .onPreferenceChange(HeaderHeightKey.self) { value in
            guard layoutMode == .compactSheet else { return }
            self.headerHeight = value
            viewModel.topPadding = value
            Debug.log("Header Height reported: \(value)")
        }
        .onAppear {
            Debug.log("ContentView.onAppear called")
            if containerSize == .zero, let windowSize = ActiveWindowScene.keyWindow?.bounds.size {
                containerSize = windowSize
            }
            syncLayoutMode(layoutMode)

            cancellableUserLocation = viewModel.userLocationSubject.sink { updatedUserLocation in
                userLocation = updatedUserLocation
            }
            mapStoppedMovingCancellable = viewModel.mapStoppedMovingSubject.sink(receiveValue: {})
        }
        .onChange(of: layoutMode) { _, newMode in
            syncLayoutMode(newMode)
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

    private func syncLayoutMode(_ newMode: AppLayoutMode) {
        viewModel.updateLayoutMode(newMode)
        if newMode == .splitSidebar, headerHeight != 0 {
            headerHeight = 0
        }
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

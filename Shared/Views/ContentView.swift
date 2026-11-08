// ContentView.swift
//
// Redesign phase 3: the adaptive root. Reads size classes and the container
// size (never the device idiom), feeds them to `AppNavigation`, and renders
// the layout for the resolved posture: `CompactLayoutView` (map + sheet) or
// `SplitLayoutView` (sidebar + map, plus inspector when expanded).

import SwiftUI
import MapKit
import BitLocalDomain
import BitLocalNavigation

struct ContentView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    @EnvironmentObject private var featureHintsController: FeatureHintsController
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var appearanceManager = AppearanceManager()
    @State private var navigation = AppNavigation()
    @State private var showingSettings = false
    @SceneStorage("navigationState") private var savedNavigationState: Data?

    @AppStorage("selectedMapType") private var storedMapType: Int = 0

    var selectedMapTypeBinding: Binding<MKMapType> {
        Binding<MKMapType>(
            get: { MKMapType.from(int: storedMapType) },
            set: { storedMapType = $0.intValue }
        )
    }

    var body: some View {
        Group {
            if navigation.posture.usesSheet {
                CompactLayoutView(
                    viewModel: viewModel,
                    elements: viewModel.mapElementsForCurrentDisplay,
                    visibleElements: viewModel.listElementsForCurrentDisplay,
                    showingSettings: $showingSettings,
                    selectedMapTypeBinding: selectedMapTypeBinding
                )
            } else {
                SplitLayoutView(
                    viewModel: viewModel,
                    elements: viewModel.mapElementsForCurrentDisplay,
                    visibleElements: viewModel.listElementsForCurrentDisplay,
                    showingSettings: $showingSettings,
                    selectedMapTypeBinding: selectedMapTypeBinding
                )
            }
        }
        .environmentObject(appearanceManager)
        .environment(navigation)
        // Posture changes swap containers without animation: resizing and folding
        // are physical, so the hardware is the animation (duo.md 3.4).
        .transaction { transaction in
            if transaction.animation != nil, postureJustChanged { transaction.animation = nil }
        }
        .onGeometryChange(for: GeometrySnapshot.self) { proxy in
            GeometrySnapshot(
                size: CGSize(
                    width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                    height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                ),
                horizontal: nil,
                vertical: nil,
                divisions: FoldGeometry.divisions(in: proxy)
            )
        } action: { snapshot in
            updateGeometry(snapshot)
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            if let geometry = navigation.geometry { updateGeometry(geometry) }
        }
        .onChange(of: verticalSizeClass) { _, _ in
            if let geometry = navigation.geometry { updateGeometry(geometry) }
        }
        // Bridge: the legacy view model still owns the merchant path; mirror it
        // into the navigation model so posture changes re-home the selection.
        .onChange(of: viewModel.path.last?.id) { _, id in
            let selection = id.flatMap(MerchantID.init(string:)).map(Selection.merchant)
            guard selection != navigation.selection else { return }
            let source: BitLocalNavigation.SelectionSource = viewModel.selectionSource == .mapAnnotation ? .map : .list
            navigation.select(selection, source: source)
            saveNavigationState()
        }
        .onChange(of: navigation.sheetDetent) { _, _ in
            saveNavigationState()
        }
        .onAppear {
            restoreNavigationState()
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
        .preferredColorScheme(colorScheme(for: appearanceManager.appearance))
    }

    @State private var postureJustChanged = false

    private func updateGeometry(_ snapshot: GeometrySnapshot) {
        var resolved = snapshot
        resolved.horizontal = horizontalSizeClass.map { $0 == .regular ? .regular : .compact }
        resolved.vertical = verticalSizeClass.map { $0 == .regular ? .regular : .compact }
        let before = navigation.posture
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            navigation.updateGeometry(resolved)
        }
        postureJustChanged = before != navigation.posture
    }

    /// Only the sheet detent is restored for now; the merchant selection is restored
    /// once the merchant detail reads from the store (phase 5).
    private func restoreNavigationState() {
        guard let savedNavigationState,
              let state = try? JSONDecoder().decode(NavigationState.self, from: savedNavigationState) else { return }
        navigation.sheetDetent = state.sheetDetent == .full ? .card : state.sheetDetent
    }

    private func saveNavigationState() {
        savedNavigationState = try? JSONEncoder().encode(navigation.restorationState)
    }

    private func colorScheme(for appearance: Appearance) -> ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Fold detection (duo.md 7). `GeometryProxy.reservedRegions(kind: .division)`
/// only exists in the iOS 27.1 SDK; CI builds with Xcode 26 today, so this
/// returns no divisions until the toolchain moves (DECISIONS.md, phase 3).
enum FoldGeometry {
    static func divisions(in proxy: GeometryProxy) -> [Division] {
        []
    }
}

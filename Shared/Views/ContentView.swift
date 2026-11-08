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
    @State private var topOcclusion: CGFloat = 0
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
                    selectedMapTypeBinding: selectedMapTypeBinding,
                    topOcclusion: topOcclusion
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            FoldGeometry.topOcclusion(in: proxy)
        } action: { occlusion in
            if topOcclusion != occlusion {
                Debug.log("Top occlusion region ends \(occlusion) pt from the window top")
                topOcclusion = occlusion
            }
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
            StoreMap.shared.setSelected(id.flatMap(MerchantID.init(string:)))
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

/// Fold detection (duo.md 7). The reserved-region API ships in the iOS 27.1 SDK
/// (Swift 6.4, Xcode 27). CI still builds with Xcode 26, so the query sits behind a
/// compiler check and older toolchains or OS versions report no regions.
enum FoldGeometry {
    static func divisions(in proxy: GeometryProxy) -> [Division] {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            // Include inactive (flat) folds so columns snap to the fold before it bends (duo.md 2).
            return proxy.reservedRegions(kind: .division, options: .includeInactive)
                .map { Division(frame: $0.frame, isActive: $0.isActive) }
        }
        #endif
        return []
    }

    /// How far down from the top of the window something occludes content (the Duo's
    /// outer camera and status strip), beyond the safe area. Zero when nothing reports.
    static func topOcclusion(in proxy: GeometryProxy) -> CGFloat {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            let regions = proxy.reservedRegions(kind: .occlusion, options: .includeInactive)
            let topBand = proxy.size.height / 3
            return regions
                .filter { $0.frame.minY < topBand }
                .map { $0.frame.maxY + proxy.safeAreaInsets.top }
                .max() ?? 0
        }
        #endif
        return 0
    }
}

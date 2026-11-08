//
//  SplitLayoutView.swift
//  bitlocal
//
//  Redesign phase 3: every non-compact posture (iPad, iPad Split View 1/2,
//  Stage Manager windows, Duo unfolded, short-and-wide windows). Sidebar +
//  map; in the expanded posture (≥ 1000 pt) merchant detail opens in an
//  inspector and the sidebar keeps the list. Chosen by width and size class,
//  never by device idiom.
//

import SwiftUI
import MapKit
import BitLocalDesign
import BitLocalNavigation

struct SplitLayoutView: View {
    @ObservedObject var viewModel: ContentViewModel
    var elements: [Element]?
    var visibleElements: [Element]
    @Binding var showingSettings: Bool
    var selectedMapTypeBinding: Binding<MKMapType>

    @Environment(AppNavigation.self) private var navigation
    @EnvironmentObject private var appearanceManager: AppearanceManager
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private let settingsPopoverSize = CGSize(width: 420, height: 560)

    private var usesInspector: Bool { navigation.posture.hasInspector }

    private var sidebarIdealWidth: CGFloat {
        navigation.posture == .compactLandscape ? LayoutMetrics.sidebarMinWidth : LayoutMetrics.sidebarIdealWidth
    }

    /// In the expanded posture the inspector shows the selection, so the sidebar
    /// stack never pushes it; writes still reach the view model so selection works.
    private var sidebarPath: Binding<[Element]> {
        Binding(
            get: { usesInspector ? [] : viewModel.path },
            set: { newPath in
                if usesInspector {
                    if !newPath.isEmpty { viewModel.path = newPath }
                } else {
                    viewModel.path = newPath
                }
            }
        )
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { usesInspector && viewModel.path.last != nil },
            set: { isPresented in
                if !isPresented, usesInspector { viewModel.path = [] }
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            mapPanel
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: inspectorPresented) {
            inspectorContent
                .inspectorColumnWidth(
                    min: LayoutMetrics.inspectorMinWidth,
                    ideal: LayoutMetrics.inspectorIdealWidth,
                    max: LayoutMetrics.inspectorMaxWidth
                )
        }
        .onChange(of: columnVisibility) { _, newValue in
            guard newValue != .all else { return }
            columnVisibility = .all
        }
        .onChange(of: viewModel.path) { _, newPath in
            if newPath.last != nil {
                _ = viewModel.consumeSelectionSource()
            } else {
                viewModel.deselectAnnotation()
            }
            viewModel.selectedElement = newPath.last
        }
        .onAppear {
            viewModel.applyTargetSheetHeight(0)
            viewModel.topPadding = 0
        }
    }

    private var sidebar: some View {
        NavigationStack(path: sidebarPath) {
            sidebarRootContent
                .navigationDestination(for: Element.self) { element in
                    detail(for: element)
                        .toolbar(removing: .sidebarToggle)
                }
                .navigationDestination(isPresented: communityDetailBindingIsPresented) {
                    communityDetailDestination
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text(verbatim: "bitlocal")
                            .font(.custom("Fredoka-Medium", size: 24, relativeTo: .title2))
                            .foregroundStyle(BrandColor.brand)
                            .lineLimit(1)
                            .fixedSize()
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel("BitLocal")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsButtonView(onSettingsSelected: { showingSettings = true })
                            .popover(isPresented: $showingSettings, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                settingsPopover
                            }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
                .toolbar(removing: .sidebarToggle)
                .clearNavigationContainerBackgroundIfAvailable()
        }
        .onChange(of: viewModel.unifiedSearchText) { _, _ in
            guard viewModel.mapDisplayMode != .communities else { return }
            viewModel.performUnifiedSearch()
        }
        // No max width: in a fold-aligned pose the system may widen the sidebar to the fold (duo.md 2.3).
        .navigationSplitViewColumnWidth(min: LayoutMetrics.sidebarMinWidth, ideal: sidebarIdealWidth)
    }

    /// The Places/Communities switch sits under the bar, full width, instead of in
    /// the bar's center, where it squeezed the wordmark to "bi…" in a narrow sidebar.
    private var sidebarRootContent: some View {
        sidebarBrowseContent
            .safeAreaInset(edge: .top, spacing: 0) {
                BrowseModePicker()
                    .padding(.horizontal, Spacing.columnEdge)
                    .padding(.bottom, Spacing.xs)
            }
    }

    @ViewBuilder
    private var sidebarBrowseContent: some View {
        if viewModel.mapDisplayMode == .communities {
            CommunitiesListView()
                .environmentObject(viewModel)
        } else {
            BusinessesListView(elements: visibleElements)
                .environmentObject(viewModel)
        }
    }

    private var mapPanel: some View {
        ZStack {
            if let elements {
                MapView(
                    elements: elements,
                    topPadding: 0,
                    bottomPadding: 0,
                    mapType: selectedMapTypeBinding.wrappedValue,
                    storeRenderToken: StoreMap.shared.renderToken
                )
                .id("PersistentMap")
                // Only vertically: on iOS 26 the sidebar floats over the detail column,
                // and a map running under it hid pins and tinted the glass sidebar.
                .ignoresSafeArea(.container, edges: .vertical)
                .onAppear {
                    viewModel.locationManager.startUpdatingLocation()
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            OpenStreetMapAttributionView()
                .padding(.leading, Spacing.columnEdge)
                .padding(.bottom, Spacing.xs)
        }
        .overlay(alignment: .topTrailing) {
            MapButtonsView(
                viewModel: viewModel,
                selectedMapTypeBinding: selectedMapTypeBinding,
                userLocation: viewModel.userLocation,
                isIPad: true
            )
            .padding(.top, Spacing.xs)
            .padding(.trailing, Spacing.columnEdge)
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let element = viewModel.path.last {
            NavigationStack {
                detail(for: element)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.path = []
                            } label: {
                                Label("Close", systemImage: "xmark")
                            }
                        }
                    }
            }
            .id(element.id)
        }
    }

    private func detail(for element: Element) -> some View {
        BusinessDetailView(
            element: element,
            userLocation: viewModel.userLocation,
            contentViewModel: viewModel
        )
        .environmentObject(viewModel)
        .clearNavigationContainerBackgroundIfAvailable()
    }

    private var settingsPopover: some View {
        NavigationStack {
            SettingsView(
                selectedMapType: selectedMapTypeBinding,
                onDone: { showingSettings = false }
            )
            .environmentObject(viewModel)
            .environmentObject(MerchantAlertsManager.shared)
            .id("split-settings-\(appearanceManager.appearance.rawValue)-\(systemColorScheme)")
        }
        .frame(
            minWidth: settingsPopoverSize.width,
            idealWidth: settingsPopoverSize.width,
            minHeight: settingsPopoverSize.height,
            idealHeight: settingsPopoverSize.height
        )
    }

    @ViewBuilder
    private var communityDetailDestination: some View {
        if let area = viewModel.presentedCommunityArea {
            CommunityDetailView(area: area)
                .id(area.id)
                .environmentObject(viewModel)
                .clearNavigationContainerBackgroundIfAvailable()
                .toolbar(removing: .sidebarToggle)
        }
    }

    private var communityDetailBindingIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.presentedCommunityArea != nil },
            set: { newValue in
                if !newValue {
                    viewModel.presentedCommunityArea = nil
                }
            }
        )
    }
}

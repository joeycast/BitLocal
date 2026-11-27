//
//  IPadLayoutView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import SwiftUI
import MapKit

struct IPadLayoutView: View {
    @Bindable var viewModel: ContentViewModel
    var elements: [Element]?
    var visibleElements: [Element]
    @Binding var showingSettings: Bool
    @Binding var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>
    @Environment(AppearanceManager.self) private var appearanceManager
    @Environment(\.colorScheme) private var systemColorScheme

    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }
    private var appearance: Appearance { appearanceManager.appearance }
    private let toolbarContentTopPadding: CGFloat = 6
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var containerSize: CGSize = .zero

    private var resolvedPopoverWidth: CGFloat {
        guard containerSize.width > 0 else { return 420 }
        return min(420, max(320, containerSize.width - 48))
    }

    private var resolvedSettingsPopoverHeight: CGFloat {
        guard containerSize.height > 0 else { return 580 }
        return min(580, max(360, containerSize.height - 110))
    }

    private var sidePanel: some View {
        NavigationStack(path: $viewModel.path) {
            sidePanelRootContentWithSafeAreaBehavior
                .navigationDestination(for: BitLocalNavigationRoute.self) { route in
                    switch route {
                    case .place(let element):
                        BusinessDetailView(
                            element: element,
                            userLocation: viewModel.userLocation,
                            contentViewModel: viewModel
                        )
                        .environment(viewModel)
                        .clearNavigationContainerBackgroundIfAvailable()
                        .toolbar(removing: .sidebarToggle)
                    case .placeComments(let element):
                        BTCMapPlaceCommentsListView(element: element)
                            .clearNavigationContainerBackgroundIfAvailable()
                            .toolbar(removing: .sidebarToggle)
                    case .allEvents:
                        AllEventsListView()
                            .environment(viewModel)
                            .clearNavigationContainerBackgroundIfAvailable()
                            .toolbar(removing: .sidebarToggle)
                    }
                }
                .navigationDestination(item: $viewModel.presentedCommunityArea) { area in
                    CommunityDetailView(area: area)
                        .id(area.id)
                        .environment(viewModel)
                        .clearNavigationContainerBackgroundIfAvailable()
                        .toolbar(removing: .sidebarToggle)
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        CustomiPadNavigationStackTitleView()
                            .padding(.top, toolbarContentTopPadding)
                            .frame(maxWidth: .infinity)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("settings_label_accessibility", systemImage: "gearshape") {
                            BitLocalHaptics.selection()
                            showingSettings = true
                        }
                        .padding(.top, toolbarContentTopPadding)
                        .popover(isPresented: $showingSettings, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                            NavigationStack {
                                SettingsView(
                                    selectedMapType: selectedMapTypeBinding,
                                    onDone: {
                                        showingSettings = false
                                    }
                                )
                                .environment(viewModel)
                                .environment(MerchantAlertsManager.shared)
                            }
                            .id("ipad-settings-\(appearance.rawValue)-\(systemColorScheme)")
                            .preferredColorScheme(effectiveColorScheme)
                            .frame(
                                minWidth: 320,
                                idealWidth: resolvedPopoverWidth,
                                minHeight: 360,
                                idealHeight: resolvedSettingsPopoverHeight
                            )
                        }
                    }
                }
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
                .toolbar(removing: .sidebarToggle)
                .clearNavigationContainerBackgroundIfAvailable()
        }
        .onChange(of: viewModel.unifiedSearchText) { _, _ in
            guard viewModel.mapDisplayMode != .communities else { return }
            viewModel.performUnifiedSearch()
        }
        .onChange(of: viewModel.isSearchActive) { _, isActive in
            guard viewModel.mapDisplayMode != .communities else { return }
            if !isActive {
                // Clearing search dismisses any persisted category chip.
                viewModel.clearMerchantSearch(userInitiated: true)
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
    }

    @ViewBuilder
    private var sidePanelRootContentWithSafeAreaBehavior: some View {
        // Respect the navigation bar top safe area so the search bar sits cleanly
        // below the toolbar on both iPadOS and iPhone Duo unfolded landscape.
        sidePanelRootContent
    }

    @ViewBuilder
    private var sidePanelRootContent: some View {
        // Both CommunitiesListView and BusinessesListView embed SheetMapModeSwitcher
        // below their search bar (always visible when currentDetent == nil on iPad/Duo).
        if viewModel.mapDisplayMode == .communities {
            CommunitiesListView()
                .environment(viewModel)
        } else {
            BusinessesListView(elements: visibleElements)
                .environment(viewModel)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidePanel
        } detail: {
            SplitMapDetailView(
                viewModel: viewModel,
                elements: elements,
                headerHeight: headerHeight,
                selectedMapTypeBinding: selectedMapTypeBinding
            )
        }
        .navigationSplitViewStyle(.balanced)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            if newSize != containerSize {
                containerSize = newSize
            }
        }
        .onChange(of: columnVisibility) { _, newValue in
            guard newValue != .all else { return }
            columnVisibility = .all
        }
        .onChange(of: viewModel.path) { _, newPath in
            let activeElement = newPath.last?.element
            if activeElement != nil {
                _ = viewModel.consumeSelectionSource()
            } else {
                viewModel.deselectAnnotation()
            }
            viewModel.selectedElement = activeElement
        }
    }

    private var effectiveColorScheme: ColorScheme? {
        switch appearance {
        case .system: return systemColorScheme
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Detail map column inside `NavigationSplitView`. Reads `isVerticalToolbarActive`
/// from the detail column environment so iPhone Duo unfolded landscape places the
/// map controls in the system vertical side rail while iPad keeps the floating pill.
private struct SplitMapDetailView: View {
    var viewModel: ContentViewModel
    var elements: [Element]?
    var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>

    @Environment(\.isVerticalToolbarActive) private var isVerticalToolbarActive
    @State private var recenterController = MapLocationRecenterController()

    private var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    var body: some View {
        ZStack {
            if let elements = elements {
                MapView(
                    elements: elements,
                    topPadding: headerHeight,
                    bottomPadding: viewModel.bottomPadding,
                    mapType: selectedMapType
                )
                .id("PersistentMap")
                .ignoresSafeArea()
                .onAppear {
                    viewModel.locationManager.startUpdatingLocation()
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if elements != nil {
                OpenStreetMapAttributionView()
                    .padding(.bottom, 7)
                    .padding(.leading, 100)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isVerticalToolbarActive {
                MapButtonsView(
                    viewModel: viewModel,
                    selectedMapTypeBinding: selectedMapTypeBinding
                )
                .padding(.trailing, 20)
                .padding(.bottom, 28)
            }
        }
        .toolbar {
            if isVerticalToolbarActive {
                MapControlToolbarContent(
                    viewModel: viewModel,
                    selectedMapTypeBinding: selectedMapTypeBinding,
                    recenterController: recenterController,
                    placement: .topBarTrailing
                )
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(removing: .sidebarToggle)
        .locationRecenterAlerts(controller: recenterController)
    }
}

// MARK: - Preview

#Preview(traits: .landscapeLeft) {
    @Previewable @State var showingSettings = true
    @Previewable @State var headerHeight: CGFloat = 80
    let viewModel = ContentViewModel()
    IPadLayoutView(
        viewModel: viewModel,
        elements: [],
        visibleElements: [],
        showingSettings: $showingSettings,
        headerHeight: $headerHeight,
        selectedMapTypeBinding: .constant(.standard)
    )
    .environment(viewModel)
    .environment(AppearanceManager())
}

//
//  IPadLayoutView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import SwiftUI
import MapKit

struct IPadLayoutView: View {
    @ObservedObject var viewModel: ContentViewModel
    var elements: [Element]?
    var visibleElements: [Element]
    @Binding var showingSettings: Bool
    @Binding var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>
    @EnvironmentObject private var appearanceManager: AppearanceManager
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
                .navigationDestination(for: Element.self) { element in
                    BusinessDetailView(
                        element: element,
                        userLocation: viewModel.userLocation,
                        contentViewModel: viewModel
                    )
                    .environmentObject(viewModel)
                    .clearNavigationContainerBackgroundIfAvailable()
                    .toolbar(removing: .sidebarToggle)
                }
                .navigationDestination(isPresented: communityDetailBindingIsPresented) {
                    communityDetailDestination
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        CustomiPadNavigationStackTitleView()
                            .padding(.top, toolbarContentTopPadding)
                            .frame(maxWidth: .infinity)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsButtonView(
                            onSettingsSelected: {
                                showingSettings = true
                            }
                        )
                        .padding(.top, toolbarContentTopPadding)
                        .popover(isPresented: $showingSettings, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                            NavigationStack {
                                SettingsView(
                                    selectedMapType: selectedMapTypeBinding,
                                    onDone: {
                                        showingSettings = false
                                    }
                                )
                                .environmentObject(viewModel)
                                .environmentObject(MerchantAlertsManager.shared)
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
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
                .toolbar(removing: .sidebarToggle)
                .clearNavigationContainerBackgroundIfAvailable()
        }
        .onChange(of: viewModel.unifiedSearchText) { _, _ in
            guard viewModel.mapDisplayMode != .communities else { return }
            viewModel.performUnifiedSearch()
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
        if viewModel.mapDisplayMode == .communities {
            CommunitiesListView()
                .environmentObject(viewModel)
        } else {
            BusinessesListView(elements: visibleElements)
                .environmentObject(viewModel)
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
            if newPath.last != nil {
                _ = viewModel.consumeSelectionSource()
            } else {
                viewModel.deselectAnnotation()
            }
            viewModel.selectedElement = newPath.last
        }
    }

    private var effectiveColorScheme: ColorScheme? {
        switch appearance {
        case .system: return systemColorScheme
        case .light:  return .light
        case .dark:   return .dark
        }
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

/// Detail map column inside `NavigationSplitView`. Reads `isVerticalToolbarActive`
/// from the detail column environment so iPhone Duo unfolded landscape places the
/// map controls in the system vertical side rail while iPad keeps the floating pill.
private struct SplitMapDetailView: View {
    @ObservedObject var viewModel: ContentViewModel
    var elements: [Element]?
    var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>

    @Environment(\.isVerticalToolbarActive) private var isVerticalToolbarActive
    @StateObject private var recenterController = MapLocationRecenterController()

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
                    selectedMapTypeBinding: selectedMapTypeBinding,
                    userLocation: viewModel.userLocation,
                    isIPad: true
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(removing: .sidebarToggle)
    }
}

// MARK: - Preview

struct IPadLayoutView_Previews: PreviewProvider {
    @State static var elements: [Element]? = []
    @State static var visibleElements: [Element] = []
    @State static var showingSettings = true
    @State static var headerHeight: CGFloat = 80
    @StateObject static var viewModel = ContentViewModel()
    @State static var mapType: MKMapType = .standard

    static var previews: some View {
        IPadLayoutView(
            viewModel: viewModel,
            elements: elements,
            visibleElements: visibleElements,
            showingSettings: $showingSettings,
            headerHeight: $headerHeight,
            selectedMapTypeBinding: .constant(.standard)
        )
        .environmentObject(viewModel)
        .previewInterfaceOrientation(.landscapeLeft)
    }
}

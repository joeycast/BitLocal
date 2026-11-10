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
        switch navigation.posture {
        case .compactLandscape:
            LayoutMetrics.sidebarMinWidth
        case .foldColumns(let division, _):
            // The browse column's trailing edge sits on the fold (duo.md 2).
            max(division.minX, LayoutMetrics.sidebarMinWidth)
        default:
            LayoutMetrics.sidebarIdealWidth
        }
    }

    private var foldStackDivision: CGRect? {
        if case .foldStack(let division, _) = navigation.posture { return division }
        return nil
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
        Group {
            if let division = foldStackDivision {
                foldStackLayout(division: division)
            } else {
                splitLayout
            }
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

    /// Fold stack (duo.md 1, 2): the map fills the region above the fold and runs
    /// under the fold's gutter (tiles may cross it); the browse panel starts at the
    /// fold's bottom edge. Detail pushes inside the panel, never an inspector.
    private func foldStackLayout(division: CGRect) -> some View {
        VStack(spacing: 0) {
            mapPanel(bottomClearance: division.height)
                .frame(height: max(division.maxY, 0))
            sidebar
                .background(.background)
        }
    }

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            mapPanel()
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
                // BitLocal's own header instead of bar items: on iOS 26 each bar item
                // got its own glass pill, which boxed the wordmark in a bubble.
                .toolbar(.hidden, for: .navigationBar)
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
                VStack(spacing: Spacing.s) {
                    HStack(alignment: .center) {
                        Text(verbatim: "bitlocal")
                            .font(.custom("Fredoka-Medium", size: 30, relativeTo: .title))
                            .foregroundStyle(BrandColor.brand)
                            .lineLimit(1)
                            .fixedSize()
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel("BitLocal")
                        Spacer(minLength: Spacing.xs)
                        SettingsButtonView(onSettingsSelected: { showingSettings = true }, style: .circle)
                            .popover(isPresented: $showingSettings, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                settingsPopover
                            }
                    }
                    BrowseModePicker()
                }
                .padding(.horizontal, Spacing.columnEdge - 4)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.s)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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

    /// `bottomClearance` keeps pins' centering, the attribution and the controls off
    /// a fold gutter that the map runs under (fold stack).
    private func mapPanel(bottomClearance: CGFloat = 0) -> some View {
        ZStack {
            MapView(
                topPadding: 0,
                bottomPadding: bottomClearance,
                mapType: selectedMapTypeBinding.wrappedValue,
                storeRenderToken: StoreMap.shared.renderToken
            )
            .id("PersistentMap")
            // Not under the leading edge: on iOS 26 the sidebar floats over the detail
            // column, and a map running under it hid pins and tinted the glass sidebar.
            // Vertically and trailing, so the map runs under the Duo's status column and an
            // iPhone's landscape notch instead of stopping at a blank strip.
            .ignoresSafeArea(.container, edges: [.vertical, .trailing])
            .onAppear {
                viewModel.locationManager.startUpdatingLocation()
            }
        }
        .overlay(alignment: .bottomLeading) {
            OpenStreetMapAttributionView()
                .padding(.leading, Spacing.columnEdge)
                .padding(.bottom, Spacing.xs + bottomClearance)
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
                .toolbar(.visible, for: .navigationBar)
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

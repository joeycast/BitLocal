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
    @Binding var showingAbout: Bool
    @Binding var showingSettings: Bool
    @Binding var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>
    
    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }
    private let aboutPopoverWidth: CGFloat = 420
    private let aboutPopoverHeight: CGFloat = 640
    private let settingsPopoverWidth: CGFloat = 420
    private let settingsPopoverHeight: CGFloat = 520
    private let toolbarContentTopPadding: CGFloat = 6
    private let sidebarRootTopCompensation: CGFloat = 30
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
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
                    ToolbarItem(placement: .topBarLeading) {
                        InfoButtonView(showingAbout: $showingAbout)
                            .padding(.top, toolbarContentTopPadding)
                            .popover(isPresented: $showingAbout, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                AboutView(onDone: {
                                    showingAbout = false
                                })
                                .frame(
                                    minWidth: aboutPopoverWidth,
                                    idealWidth: aboutPopoverWidth,
                                    minHeight: aboutPopoverHeight,
                                    idealHeight: aboutPopoverHeight
                                )
                            }
                    }
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
                                .environmentObject(MerchantAlertsManager.shared)
                            }
                            .frame(
                                minWidth: settingsPopoverWidth,
                                idealWidth: settingsPopoverWidth,
                                minHeight: settingsPopoverHeight,
                                idealHeight: settingsPopoverHeight
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
        .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 430)
    }

    @ViewBuilder
    private var sidePanelRootContentWithSafeAreaBehavior: some View {
        if #available(iOS 26.0, *) {
            sidePanelRootContent
                // The iPadOS 26 transparent nav bar keeps the toolbar animation we want,
                // but it also leaves extra visible space before our custom search row.
                .padding(.top, sidebarRootTopCompensation)
                .ignoresSafeArea(.container, edges: .top)
        } else {
            sidePanelRootContent
        }
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
    
    private var mapPanel: some View {
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
                .overlay(
                    OpenStreetMapAttributionView()
                        .padding(.bottom, 7)
                        .padding(.leading, 100),
                    alignment: .bottomLeading
                )
            }
        }
        .overlay(
            MapButtonsView(
                viewModel: viewModel,
                selectedMapTypeBinding: selectedMapTypeBinding,
                userLocation: viewModel.userLocation,
                isIPad: true
            )
            .padding(.trailing, 20)
            .padding(.bottom, 28),
            alignment: .bottomTrailing
        )
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidePanel
        } detail: {
            mapPanel
        }
        .navigationSplitViewStyle(.balanced)
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
    
    private func colorSchemeFor(_ appearance: Appearance) -> ColorScheme? {
        switch appearance {
        case .system: return nil
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

// MARK: - Preview

struct IPadLayoutView_Previews: PreviewProvider {
    @State static var elements: [Element]? = []
    @State static var visibleElements: [Element] = []
    @State static var showingAbout = false
    @State static var showingSettings = true
    @State static var headerHeight: CGFloat = 80
    @StateObject static var viewModel = ContentViewModel()
    @State static var mapType: MKMapType = .standard
    
    static var previews: some View {
        IPadLayoutView(
            viewModel: viewModel,
            elements: elements,
            visibleElements: visibleElements,
            showingAbout: $showingAbout,
            showingSettings: $showingSettings,
            headerHeight: $headerHeight,
            selectedMapTypeBinding: .constant(.standard)
        )
        .environmentObject(viewModel)
        .previewInterfaceOrientation(.landscapeLeft)
    }
}

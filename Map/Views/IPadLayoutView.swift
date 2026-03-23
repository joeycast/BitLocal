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
    
    private var sidePanel: some View {
        NavigationStack(path: $viewModel.path) {
            Group {
                if viewModel.mapDisplayMode == .communities {
                    CommunitiesListView()
                        .environmentObject(viewModel)
                } else {
                    BusinessesListView(elements: visibleElements)
                        .environmentObject(viewModel)
                }
            }
                .navigationDestination(for: Element.self) { element in
                    BusinessDetailView(
                        element: element,
                        userLocation: viewModel.userLocation,
                        contentViewModel: viewModel
                    ).environmentObject(viewModel)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        InfoButtonView(showingAbout: $showingAbout)
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
                            .frame(maxWidth: .infinity)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsButtonView(
                            onSettingsSelected: {
                                showingSettings = true
                            }
                        )
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
                        .opacity(1)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: viewModel.unifiedSearchText) { _, _ in
            guard viewModel.mapDisplayMode != .communities else { return }
            viewModel.performUnifiedSearch()
        }
        .sheet(item: $viewModel.presentedCommunityArea) { area in
            NavigationStack {
                CommunityDetailView(area: area)
                    .environmentObject(viewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                viewModel.presentedCommunityArea = nil
                            }
                        }
                    }
            }
        }
        .frame(width: calculateSidePanelWidth(screenWidth: UIScreen.main.bounds.width))
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
        HStack(spacing: 0) {
            sidePanel
            mapPanel
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
    
    private func calculateSidePanelWidth(screenWidth: CGFloat) -> CGFloat {
        if screenWidth <= 744 {
            return screenWidth * 0.4
        } else {
            return screenWidth * 0.35
        }
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

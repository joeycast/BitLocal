//
//  BottomSheetContentView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI
import Foundation // for Debug logging
import UIKit
import CryptoKit
import MapKit
import Observation

struct BottomSheetContentView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    @Environment(FeatureHintsController.self) private var featureHintsController
    @Environment(\.colorScheme) private var colorScheme

    var visibleElements: [Element]
    @Binding var currentDetent: PresentationDetent
    var preferredLeadingWidth: CGFloat? = nil

    private var glassContrastScrimOpacity: Double {
        if currentDetent == .large {
            return 0
        }
        return colorScheme == .dark ? 0.18 : 0.28
    }

    var body: some View {
        navigationStack
            .background {
                // Softens saturated map blues/greens behind translucent Liquid Glass
                // sheets so body and secondary text stay legible (≥4.5:1 contrast).
                Color(.systemBackground)
                    .opacity(glassContrastScrimOpacity)
                    .ignoresSafeArea()
            }
            .ignoresSafeArea(edges: .bottom)
            // UIKit reader reports screen-bottom → sheet-top using the presentation
            // frame (not NavigationStack layout height), so map buttons clear the card,
            // and applies preferredLeadingWidth directly to UISheetPresentationController.
            .background {
                SheetEdgeHeightReader(
                    preferredLeadingWidth: preferredLeadingWidth,
                    onHeightChange: { height in
                        viewModel.reportSheetHeight(height)
                    },
                    onMotionSettled: { height in
                        viewModel.reportSheetMotionSettled(height)
                    }
                )
            }
            .onAppear {
                featureHintsController.markMainUIVisible()
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
            .onChange(of: viewModel.path) { _, newPath in
                Debug.log("BottomSheet path changed (iPhone scenario)")
                if let activeElement = newPath.last?.element {
                    _ = viewModel.consumeSelectionSource()
                    viewModel.selectedElement = activeElement
                } else {
                    viewModel.deselectAnnotation()
                }
            }
    }

    private var navigationStack: some View {
        NavigationStack(path: $viewModel.path) {
            sheetRootContentWithSafeAreaBehavior
                .modifier(RootSheetNavigationBarModifier())
                .disableVerticalToolbarIfAvailable()
                .navigationDestination(for: BitLocalNavigationRoute.self) { route in
                    switch route {
                    case .place(let element):
                        businessDetailDestination(for: element)
                    case .placeComments(let element):
                        BTCMapPlaceCommentsListView(element: element)
                            .clearNavigationContainerBackgroundIfAvailable()
                            .disableVerticalToolbarIfAvailable()
                    case .allEvents:
                        AllEventsListView()
                            .environmentObject(viewModel)
                            .clearNavigationContainerBackgroundIfAvailable()
                            .disableVerticalToolbarIfAvailable()
                    }
                }
                .navigationDestination(item: $viewModel.presentedCommunityArea) { area in
                    CommunityDetailView(
                        area: area,
                        currentDetent: currentDetentBinding
                    )
                    .id(area.id)
                    .environmentObject(viewModel)
                    .clearNavigationContainerBackgroundIfAvailable()
                    .disableVerticalToolbarIfAvailable()
                }
                .clearNavigationContainerBackgroundIfAvailable()
        }
        .disableVerticalToolbarIfAvailable()
    }

    @ViewBuilder
    private var sheetRootContentWithSafeAreaBehavior: some View {
        if #available(iOS 26.0, *) {
            sheetRootContent
                .ignoresSafeArea(.container, edges: .top)
        } else {
            sheetRootContent
        }
    }

    @ViewBuilder
    private var sheetRootContent: some View {
        if viewModel.mapDisplayMode == .communities {
            CommunitiesListView(currentDetent: currentDetent)
                .environmentObject(viewModel)
        } else {
            BusinessesListView(
                elements: visibleElements,
                currentDetent: currentDetentBinding
            )
            .environmentObject(viewModel)
        }
    }

    private func businessDetailDestination(for element: Element) -> some View {
        BusinessDetailView(
            element: element,
            userLocation: viewModel.userLocation,
            contentViewModel: viewModel,
            currentDetent: currentDetentBinding
        )
        .id(element.id)
        .clearNavigationContainerBackgroundIfAvailable()
        .disableVerticalToolbarIfAvailable()
    }

    private var currentDetentBinding: Binding<PresentationDetent?> {
        Binding(
            get: { currentDetent },
            set: { newValue in
                if let newValue {
                    currentDetent = newValue
                }
            }
        )
    }
}

private struct RootSheetNavigationBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
        } else {
            content
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}

/// Clear labeled mode switcher (`Merchants | Communities`) embedded inside the
/// sheet/sidebar header so users never have to guess what an icon-only button does.
struct SheetMapModeSwitcher: View {
    @ObservedObject var viewModel: ContentViewModel

    private var selectionBinding: Binding<MapDisplayMode> {
        Binding(
            get: { viewModel.mapDisplayMode },
            set: { newMode in
                viewModel.setMapDisplayMode(newMode)
            }
        )
    }

    var body: some View {
        Picker("Map display mode", selection: selectionBinding) {
            Text(NSLocalizedString("Merchants", comment: "Segmented control option for Bitcoin merchants"))
                .tag(MapDisplayMode.merchants)
            Text(NSLocalizedString("Communities", comment: "Segmented control option for Bitcoin communities"))
                .tag(MapDisplayMode.communities)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .featureHintAnchor(.communityToggle)
    }
}

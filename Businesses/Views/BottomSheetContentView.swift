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
    @Environment(ContentViewModel.self) var viewModel
    @Environment(FeatureHintsController.self) private var featureHintsController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var visibleElements: [Element]
    @Binding var currentDetent: PresentationDetent
    var preferredLeadingWidth: CGFloat? = nil

    private var glassContrastScrimOpacity: Double {
        if colorSchemeContrast == .increased {
            return 0.96
        }
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
        @Bindable var viewModel = viewModel
        return NavigationStack(path: $viewModel.path) {
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
                            .environment(viewModel)
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
                    .environment(viewModel)
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
                .environment(viewModel)
        } else {
            BusinessesListView(
                elements: visibleElements,
                currentDetent: currentDetentBinding
            )
            .environment(viewModel)
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

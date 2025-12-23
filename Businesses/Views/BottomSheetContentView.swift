//
//  BottomSheetContentView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI
import Foundation // for Debug logging

@available(iOS 17.0, *)
struct BottomSheetContentView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    var visibleElements: [Element]
    @Binding var currentDetent: PresentationDetent

    var body: some View {
        GeometryReader { geometry in
            VStack {
                NavigationStack(path: $viewModel.path) {
                    BusinessesListView(
                        elements: visibleElements,
                        currentDetent: currentDetent
                    )
                        .environmentObject(viewModel)
                        .navigationDestination(for: Element.self) { element in
                            BusinessDetailView(
                                element: element,
                                userLocation: viewModel.userLocation,
                                contentViewModel: viewModel,
                                currentDetent: currentDetent
                            )
                            .id(element.id)
                            .clearNavigationContainerBackgroundIfAvailable()
                        }
                        .clearNavigationContainerBackgroundIfAvailable()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                DispatchQueue.main.async {
                    let bottomSheetHeight = geometry.size.height
                    if viewModel.bottomPadding != bottomSheetHeight {
                        viewModel.bottomPadding = bottomSheetHeight
                        Debug.log("Accurate Bottom Sheet Height: \(bottomSheetHeight)")
                    }
                }
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                viewModel.bottomPadding = newHeight
                Debug.log("BottomSheetContentView height updated: \(newHeight)")
            }
            .onChange(of: viewModel.path) { _, newPath in
                Debug.log("BottomSheet path changed (iPhone scenario)")
                if let selectedElement = newPath.last {
                    // If detail view is pushed, zoom to element
                    if viewModel.consumeSelectionSource() == .mapAnnotation {
                        viewModel.zoomToElement(selectedElement)
                    }
                    viewModel.selectedElement = selectedElement
                } else {
                    // If no element is selected (path is empty), deselect annotation
                    viewModel.deselectAnnotation()
                }
            }
        }
    }
}

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

    var body: some View {
        GeometryReader { geometry in
            VStack {
                NavigationStack(path: $viewModel.path) {
                    BusinessesListView(elements: visibleElements)
                        .environmentObject(viewModel)
                        .navigationDestination(for: Element.self) { element in
                            BusinessDetailView(
                                element: element,
                                userLocation: viewModel.userLocation,
                                contentViewModel: viewModel
                            )
                            .id(element.id)
                        }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .onAppear {
                DispatchQueue.main.async {
                    let bottomSheetHeight = geometry.size.height
                    if viewModel.bottomPadding != bottomSheetHeight {
                        viewModel.bottomPadding = bottomSheetHeight
                        Debug.log("Accurate Bottom Sheet Height: \(bottomSheetHeight)")
                    }
                }
            }
            .onChange(of: geometry.size.height) { newHeight in
                viewModel.bottomPadding = newHeight
                Debug.log("BottomSheetContentView height updated: \(newHeight)")
            }
            .onChange(of: viewModel.path) { newPath in
                Debug.log("BottomSheet path changed (iPhone scenario)")
                if let selectedElement = newPath.last {
                    // If detail view is pushed, zoom to element
                    viewModel.zoomToElement(selectedElement)
                } else {
                    // If no element is selected (path is empty), deselect annotation
                    viewModel.deselectAnnotation()
                }
            }
        }
    }
}

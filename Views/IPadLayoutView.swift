//
//  IPadLayoutView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI
import MapKit

@available(iOS 17.0, *)
struct IPadLayoutView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Binding var elements: [Element]?
    @Binding var visibleElements: [Element]
    @Binding var showingAbout: Bool
    @Binding var showingSettings: Bool
    @Binding var headerHeight: CGFloat
    var selectedMapTypeBinding: Binding<MKMapType>
    @AppStorage("appearance") private var appearance: Appearance = .system

    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    @State private var settingsButtonFrame: CGRect = .zero

    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    private var sidePanel: some View {
        NavigationStack(path: $viewModel.path) {
            BusinessesListView(elements: visibleElements)
                .environmentObject(viewModel)
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
                            .padding(.trailing)
                    }
                    ToolbarItem(placement: .principal) {
                        CustomiPadNavigationStackTitleView()
                            .frame(maxWidth: .infinity)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsButtonView(
                            selectedMapType: selectedMapTypeBinding,
                            appearance: $appearance,
                            distanceUnit: $distanceUnit,
                            onSettingsSelected: {
                                withAnimation { showingSettings.toggle() }
                            },
                            onButtonFrameChange: { frame in settingsButtonFrame = frame }
                        )
                        .opacity(1)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if showingSettings {
                        Color.black.opacity(0.01)
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation { showingSettings = false } }
                        CompactSettingsPopoverView(
                            selectedMapType: selectedMapTypeBinding,
                            onDone: { withAnimation { showingSettings = false } }
                        )
                        .position(x: settingsButtonFrame.maxX + 275, y: settingsButtonFrame.maxY + 175)
                        .transition(.scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity))
                        .zIndex(2)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.65, blendDuration: 0.25), value: showingSettings)
        }
        .frame(width: calculateSidePanelWidth(screenWidth: UIScreen.main.bounds.width))
        .navigationBarTitleDisplayMode(.automatic)
    }

    private var mapPanel: some View {
        ZStack {
            if let elements = elements {
                MapView(
                    elements: .constant(elements),
                    topPadding: headerHeight,
                    bottomPadding: viewModel.bottomPadding,
                    mapType: selectedMapType
                )
                .ignoresSafeArea()
                .onAppear {
                    viewModel.locationManager.requestWhenInUseAuthorization()
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
            .padding(.trailing, 20),
            alignment: .bottomTrailing
        )
    }

    private var overlayGroup: some View {
        Group {
            if showingAbout {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showingAbout = false }
                    AboutView()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(radius: 10)
                        )
                        .padding(40)
                }
            }
        }
    }

    var body: some View {
        let screenWidth = UIScreen.main.bounds.width

        HStack(spacing: 0) {
            sidePanel
            mapPanel
        }
        .onChange(of: viewModel.path) { newPath in
            if let selectedElement = newPath.last {
                viewModel.zoomToElement(selectedElement)
            } else {
                viewModel.deselectAnnotation()
            }
            viewModel.selectedElement = newPath.last
        }
        .overlay(overlayGroup)
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

@available(iOS 17.0, *)
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
            elements: $elements,
            visibleElements: $visibleElements,
            showingAbout: $showingAbout,
            showingSettings: $showingSettings,
            headerHeight: $headerHeight,
            selectedMapTypeBinding: .constant(.standard)
        )
        .environmentObject(viewModel)
        .previewInterfaceOrientation(.landscapeLeft)
    }
}

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
    var appearance: Appearance

    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    var body: some View {
        let screenWidth = UIScreen.main.bounds.width

        HStack(spacing: 0) {
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
                        ToolbarItem(placement: .navigationBarLeading) {
                            SettingsButtonView(showingSettings: $showingSettings)
                                .opacity(0)
                        }
                        ToolbarItem(placement: .principal) {
                            CustomiPadNavigationStackTitleView()
                                .frame(maxWidth: .infinity)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            InfoButtonView(showingAbout: $showingAbout)
                        }
                    }
            }
            .frame(width: calculateSidePanelWidth(screenWidth: screenWidth))
            .navigationBarTitleDisplayMode(.automatic)

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
        .onChange(of: viewModel.path) { newPath in
            if let selectedElement = newPath.last {
                viewModel.zoomToElement(selectedElement)
            } else {
                viewModel.deselectAnnotation()
            }
            viewModel.selectedElement = newPath.last
        }
        .overlay(
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
                if showingSettings {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture { showingSettings = false }
                        SettingsView(selectedMapType: selectedMapTypeBinding)
                            .preferredColorScheme(colorSchemeFor(appearance))
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(radius: 10)
                            )
                            .padding(40)
                    }
                }
            }
        )
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
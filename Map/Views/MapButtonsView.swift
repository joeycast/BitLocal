//
//  MapButtonsView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import Combine
import MapKit
import Observation
import SwiftUI

enum LocationRecenterAlert: Identifiable, Equatable {
    case permissionDenied
    case timeout

    var id: Self { self }
}

@MainActor
@Observable
final class MapLocationRecenterController {
    var activeAlert: LocationRecenterAlert?

    @ObservationIgnored private var locationCancellable: AnyCancellable?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    func handleRecenterTap(viewModel: ContentViewModel) {
        switch viewModel.locationManager.authorizationStatus {
        case .denied, .restricted:
            activeAlert = .permissionDenied
        case .notDetermined:
            requestAndCenterOnNextLocation(viewModel: viewModel)
        case .authorizedAlways, .authorizedWhenInUse:
            if viewModel.userLocation != nil {
                viewModel.centerMapToUserLocation()
            } else {
                requestAndCenterOnNextLocation(viewModel: viewModel)
            }
        @unknown default:
            requestAndCenterOnNextLocation(viewModel: viewModel)
        }
    }

    func cancel() {
        locationCancellable?.cancel()
        locationCancellable = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func requestAndCenterOnNextLocation(viewModel: ContentViewModel) {
        cancel()
        viewModel.locationManager.requestWhenInUseAuthorization()
        viewModel.isUpdatingLocation = true
        viewModel.locationManager.startUpdatingLocation()

        locationCancellable = viewModel.$userLocation
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak viewModel] _ in
                guard let self, let viewModel else { return }
                self.cancel()
                viewModel.centerMapToUserLocation()
                viewModel.locationManager.stopUpdatingLocation()
                viewModel.isUpdatingLocation = false
            }

        timeoutTask = Task { @MainActor [weak self, weak viewModel] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, let viewModel, viewModel.isUpdatingLocation else { return }
            self.cancel()
            self.activeAlert = .timeout
            viewModel.locationManager.stopUpdatingLocation()
            viewModel.isUpdatingLocation = false
        }
    }
}

private struct LocationRecenterAlertsModifier: ViewModifier {
    let controller: MapLocationRecenterController
    @Environment(\.openURL) private var openURL

    private var permissionDeniedBinding: Binding<Bool> {
        Binding(
            get: { controller.activeAlert == .permissionDenied },
            set: { isPresented in
                if !isPresented, controller.activeAlert == .permissionDenied {
                    controller.activeAlert = nil
                }
            }
        )
    }

    private var timeoutBinding: Binding<Bool> {
        Binding(
            get: { controller.activeAlert == .timeout },
            set: { isPresented in
                if !isPresented, controller.activeAlert == .timeout {
                    controller.activeAlert = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert("location_alert_title", isPresented: permissionDeniedBinding) {
                Button("open_settings_button") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                }
                Button("ok_button", role: .cancel) {}
            } message: {
                Text("location_settings_message")
            }
            .alert("location_alert_title", isPresented: timeoutBinding) {}
    }
}

extension View {
    func locationRecenterAlerts(controller: MapLocationRecenterController) -> some View {
        modifier(LocationRecenterAlertsModifier(controller: controller))
    }
}

/// Native SwiftUI toolbar items for map controls so iPhone Duo renders them
/// directly inside the system vertical side button bar.
/// Merchants ↔ Communities switching lives in the labeled sheet mode switcher,
/// keeping the vertical rail uncluttered with two crisp, balanced map controls.
struct MapControlToolbarContent: ToolbarContent {
    @ObservedObject var viewModel: ContentViewModel
    var selectedMapTypeBinding: Binding<MKMapType>
    var recenterController: MapLocationRecenterController
    var placement: ToolbarItemPlacement = .bottomBar
    var colorScheme: ColorScheme? = nil

    private var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    var body: some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            ToolbarItemGroup(placement: placement) {
                mapTypeButton
                recenterButton
            }
            .visibilityPriority(.high)
        } else {
            legacyToolbarGroup
        }
        #else
        legacyToolbarGroup
        #endif
    }

    private var legacyToolbarGroup: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            mapTypeButton
            recenterButton
        }
    }

    private var mapTypeButton: some View {
        Button {
            BitLocalHaptics.selection()
            selectedMapTypeBinding.wrappedValue = (selectedMapType == .standard) ? .hybrid : .standard
        } label: {
            Label(
                selectedMapType == .standard ? "Show satellite map" : "Show standard map",
                systemImage: selectedMapType == .hybrid ? "map" : "globe"
            )
            .foregroundStyle(.primary)
            .id("map-type-\(selectedMapType == .hybrid)-\(colorScheme == .dark)")
        }
        .tint(.primary)
    }

    private var recenterButton: some View {
        Button {
            BitLocalHaptics.lightTap()
            recenterController.handleRecenterTap(viewModel: viewModel)
        } label: {
            Label("Center map on location", systemImage: "location")
                .foregroundStyle(.primary)
                .id("recenter-\(colorScheme == .dark)")
        }
        .tint(.primary)
    }
}

struct MapButtonsView: View {
    @ObservedObject var viewModel: ContentViewModel
    var selectedMapTypeBinding: Binding<MKMapType>
    var useMonochromeIcons: Bool = false
    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var recenterController = MapLocationRecenterController()

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        controlPill
            .locationRecenterAlerts(controller: recenterController)
    }

    private var controlPill: some View {
        let controlWidth: CGFloat = isRegularWidth ? 52 : 46
        let controlHeight: CGFloat = isRegularWidth ? 46 : 44

        return VStack(spacing: 0) {
            Button(action: toggleMapType) {
                mapTypeIcon
                    .frame(width: controlWidth, height: controlHeight)
            }
            .accessibilityLabel(selectedMapType == .standard ? "Show satellite map" : "Show standard map")

            Divider()
                .padding(.horizontal, 8)

            Button(action: handleRecenterTap) {
                Image(systemName: useMonochromeIcons ? "location" : "location.fill")
                    .font(.subheadline.weight(useMonochromeIcons ? .medium : .semibold))
                    .foregroundStyle(useMonochromeIcons ? Color.primary : Color.accentColor)
                    .frame(width: controlWidth, height: controlHeight)
            }
            .accessibilityLabel("Center map on location")

            if !useMonochromeIcons {
                Divider()
                    .padding(.horizontal, 8)

                Button {
                    Debug.log("⏱ mapMode button TAPPED")
                    viewModel.toggleMapMode()
                    Debug.log("⏱ mapMode button action DONE")
                } label: {
                    mapModeIcon
                        .frame(width: controlWidth, height: controlHeight)
                }
                .accessibilityLabel(
                    viewModel.mapDisplayMode == .merchants
                        ? LocalizedStringKey("Show communities")
                        : LocalizedStringKey("Show merchants")
                )
                .accessibilityValue(
                    viewModel.mapDisplayMode == .merchants
                        ? LocalizedStringKey("Merchants map")
                        : LocalizedStringKey("Communities map")
                )
                .accessibilityHint("Switches between merchant pins and community areas")
            }
        }
        .frame(width: controlWidth)
        .modifier(GlassCapsuleBackground())
        .fixedSize()
    }

    private func toggleMapType() {
        let newType: MKMapType = (selectedMapType == .standard) ? .hybrid : .standard
        selectedMapTypeBinding.wrappedValue = newType
    }

    private func handleRecenterTap() {
        recenterController.handleRecenterTap(viewModel: viewModel)
    }

    private var mapTypeIcon: some View {
        ZStack {
            Image(systemName: useMonochromeIcons ? "map" : "map.fill")
                .font(.subheadline.weight(useMonochromeIcons ? .medium : .semibold))
                .foregroundStyle(.primary)
                .opacity(selectedMapType == .hybrid ? 1 : 0)
            Image(systemName: useMonochromeIcons ? "globe" : "globe.americas.fill")
                .font(.subheadline.weight(useMonochromeIcons ? .medium : .semibold))
                .foregroundStyle(.primary)
                .opacity(selectedMapType == .hybrid ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.16), value: selectedMapType == .hybrid)
    }

    private var mapModeIcon: some View {
        let iconColor: Color = useMonochromeIcons ? .primary : .accentColor
        return ZStack {
            Image(systemName: "person.3.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(iconColor)
                .opacity(viewModel.mapDisplayMode == .merchants ? 1 : 0)
            Image(systemName: "mappin.and.ellipse")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(iconColor)
                .opacity(viewModel.mapDisplayMode == .merchants ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.16), value: viewModel.mapDisplayMode == .merchants)
    }
}

private struct GlassCapsuleBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                .clipShape(Capsule())
        }
    }
}

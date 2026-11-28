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

        locationCancellable = viewModel.userLocationSubject
            .compactMap { $0 }
            .first()
            .receive(on: RunLoop.main)
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

/// Native SwiftUI toolbar items for map controls so iPhone Duo and iPad render them
/// directly inside the system toolbar with full Merchants ↔ Communities parity.
struct MapControlToolbarContent: ToolbarContent {
    var viewModel: ContentViewModel
    var selectedMapTypeBinding: Binding<MKMapType>
    var recenterController: MapLocationRecenterController
    var placement: ToolbarItemPlacement = .bottomBar
    var colorScheme: ColorScheme? = nil

    private var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    var body: some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            ToolbarItemGroup(placement: placement) {
                mapModeButton
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
            mapModeButton
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
                selectedMapType == .standard
                    ? LocalizedStringKey("Show satellite map")
                    : LocalizedStringKey("Show standard map"),
                systemImage: selectedMapType == .hybrid ? "map.fill" : "globe.americas.fill"
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
            Label("Center map on location", systemImage: "location.fill")
                .foregroundStyle(.primary)
                .id("recenter-\(colorScheme == .dark)")
        }
        .tint(.primary)
    }

    private var mapModeButton: some View {
        let isCommunities = viewModel.mapDisplayMode == .communities
        return Button {
            BitLocalHaptics.selection()
            viewModel.toggleMapMode()
        } label: {
            Label(
                isCommunities
                    ? LocalizedStringKey("Show merchants")
                    : LocalizedStringKey("Show communities"),
                systemImage: isCommunities ? "mappin.and.ellipse" : "person.2.fill"
            )
            .foregroundStyle(.primary)
            .id("map-mode-\(isCommunities)-\(colorScheme == .dark)")
        }
        .tint(.primary)
        .accessibilityValue(
            isCommunities
                ? LocalizedStringKey("Communities map")
                : LocalizedStringKey("Merchants map")
        )
        .accessibilityHint("Switches between merchant pins and community areas")
        .featureHintAnchor(.communityToggle)
    }
}

struct MapButtonsView: View {
    var viewModel: ContentViewModel
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
            Button {
                BitLocalHaptics.selection()
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
            .featureHintAnchor(.communityToggle)

            Divider()
                .padding(.horizontal, 8)

            Button(action: toggleMapType) {
                mapTypeIcon
                    .frame(width: controlWidth, height: controlHeight)
            }
            .accessibilityLabel(
                selectedMapType == .standard
                    ? LocalizedStringKey("Show satellite map")
                    : LocalizedStringKey("Show standard map")
            )

            Divider()
                .padding(.horizontal, 8)

            Button(action: handleRecenterTap) {
                Image(systemName: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: controlWidth, height: controlHeight)
            }
            .accessibilityLabel("Center map on location")
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
            Image(systemName: "map.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .opacity(selectedMapType == .hybrid ? 1 : 0)
            Image(systemName: "globe.americas.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .opacity(selectedMapType == .hybrid ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.16), value: selectedMapType == .hybrid)
    }

    private var mapModeIcon: some View {
        let isCommunities = viewModel.mapDisplayMode == .communities
        return ZStack {
            Image(systemName: "person.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .opacity(isCommunities ? 0 : 1)
            Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .opacity(isCommunities ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.16), value: isCommunities)
    }
}

private struct GlassCapsuleBackground: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if colorSchemeContrast == .increased {
            content
                .background(Color(.systemBackground), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
        } else if #available(iOS 26.0, *) {
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

//
//  MapButtonsView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import Combine
import SwiftUI
import MapKit
import UIKit

@MainActor
final class MapLocationRecenterController: ObservableObject {
    private var locationCancellable: AnyCancellable?
    private var timeoutWorkItem: DispatchWorkItem?

    func handleRecenterTap(viewModel: ContentViewModel) {
        switch viewModel.locationManager.authorizationStatus {
        case .denied, .restricted:
            presentLocationSettingsAlert()
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
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
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

        let workItem = DispatchWorkItem { [weak self, weak viewModel] in
            guard let self, let viewModel, viewModel.isUpdatingLocation else { return }
            self.cancel()
            self.presentLocationTimeoutAlert()
            viewModel.locationManager.stopUpdatingLocation()
            viewModel.isUpdatingLocation = false
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }

    private func presentLocationTimeoutAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("location_alert_title", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(.init(title: NSLocalizedString("ok_button", comment: ""),
                              style: .default))
        presentAlert(alert)
    }

    private func presentLocationSettingsAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("location_alert_title", comment: ""),
            message: NSLocalizedString("location_settings_message", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(.init(title: NSLocalizedString("open_settings_button", comment: ""),
                              style: .default,
                              handler: { _ in
                                  guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
                                        UIApplication.shared.canOpenURL(settingsURL) else {
                                      return
                                  }
                                  UIApplication.shared.open(settingsURL)
                              }))
        alert.addAction(.init(title: NSLocalizedString("ok_button", comment: ""),
                              style: .cancel))
        presentAlert(alert)
    }

    private func presentAlert(_ alert: UIAlertController) {
        if let rootVC = ActiveWindowScene.keyWindow?.rootViewController {
            rootVC.topMostViewController()
                .present(alert, animated: true)
        }
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
        ToolbarItemGroup(placement: placement) {
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
}

struct MapButtonsView: View {
    @ObservedObject var viewModel: ContentViewModel
    var selectedMapTypeBinding: Binding<MKMapType>
    var userLocation: CLLocation?
    var isIPad: Bool
    var useMonochromeIcons: Bool = false
    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }

    @StateObject private var recenterController = MapLocationRecenterController()

    var body: some View {
        controlPill
    }

    private var controlPill: some View {
        let controlWidth: CGFloat = isIPad ? 52 : 46
        let controlHeight: CGFloat = isIPad ? 46 : 42

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
                    .font(.system(size: useMonochromeIcons ? 15 : 14, weight: useMonochromeIcons ? .medium : .semibold))
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
                        ? NSLocalizedString("Show communities", comment: "VoiceOver label to switch map to communities")
                        : NSLocalizedString("Show merchants", comment: "VoiceOver label to switch map to merchants")
                )
                .accessibilityValue(
                    viewModel.mapDisplayMode == .merchants
                        ? NSLocalizedString("Merchants map", comment: "VoiceOver current map mode value")
                        : NSLocalizedString("Communities map", comment: "VoiceOver current map mode value")
                )
                .accessibilityHint(
                    NSLocalizedString(
                        "Switches between merchant pins and community areas",
                        comment: "VoiceOver hint for map mode toggle"
                    )
                )
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
                .font(.system(size: useMonochromeIcons ? 15 : 14, weight: useMonochromeIcons ? .medium : .semibold))
                .foregroundStyle(.primary)
                .opacity(selectedMapType == .hybrid ? 1 : 0)
            Image(systemName: useMonochromeIcons ? "globe" : "globe.americas.fill")
                .font(.system(size: useMonochromeIcons ? 15 : 14, weight: useMonochromeIcons ? .medium : .semibold))
                .foregroundStyle(.primary)
                .opacity(selectedMapType == .hybrid ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.16), value: selectedMapType == .hybrid)
    }

    private var mapModeIcon: some View {
        let iconColor: Color = useMonochromeIcons ? .primary : .accentColor
        return ZStack {
            Image(systemName: "person.3.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .opacity(viewModel.mapDisplayMode == .merchants ? 1 : 0)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
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

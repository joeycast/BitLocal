//
//  MapButtonsView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import SwiftUI
import MapKit
import UIKit

@available(iOS 17.0, *)
struct MapButtonsView: View {
    @ObservedObject var viewModel: ContentViewModel
    var selectedMapTypeBinding: Binding<MKMapType>
    var userLocation: CLLocation?
    var isIPad: Bool
    var selectedMapType: MKMapType { selectedMapTypeBinding.wrappedValue }
    
    // 🔑 State to know when the button was tapped and we should center on next location update:
    @State private var shouldCenterOnLocation = false
    
    var body: some View {
        Group {
            if isIPad {
                legacyStackButtons
            } else {
                iPhoneControlPill
            }
        }
        // 🔄 FIXED: Watch for the first non-nil userLocation after tapping and use forced centering
        .onReceive(viewModel.$userLocation.compactMap { $0 }) { newLocation in
            guard shouldCenterOnLocation else { return }
            // FIXED: Use centerMapToUserLocation which forces centering
            viewModel.centerMapToUserLocation()
            shouldCenterOnLocation = false
            viewModel.locationManager.stopUpdatingLocation()
            viewModel.isUpdatingLocation = false
        }
    }

    private var legacyStackButtons: some View {
        VStack(spacing: 10) {
            // Community / Merchants toggle
            Button {
                viewModel.toggleMapMode()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .shadow(radius: 3)
                    Image(systemName: viewModel.mapDisplayMode == .merchants
                          ? "person.3.fill" : "mappin.and.ellipse")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel(viewModel.mapDisplayMode == .merchants
                                ? "Show communities" : "Show merchants")

            Button(action: toggleMapType) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .shadow(radius: 3)
                    Image(systemName: selectedMapType == .standard ? "map.fill" : "globe.americas.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Button(action: handleRecenterTap) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .shadow(radius: 3)
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var iPhoneControlPill: some View {
        VStack(spacing: 0) {
            Button(action: toggleMapType) {
                mapTypeIcon
                    .frame(width: 46, height: 42)
            }
            .accessibilityLabel(selectedMapType == .standard ? "Show satellite map" : "Show standard map")

            Divider()
                .padding(.horizontal, 8)

            Button(action: handleRecenterTap) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 42)
            }
            .accessibilityLabel("Center map on location")

            Divider()
                .padding(.horizontal, 8)

            Button {
                Debug.log("⏱ mapMode button TAPPED")
                viewModel.toggleMapMode()
                Debug.log("⏱ mapMode button action DONE")
            } label: {
                mapModeIcon
                    .frame(width: 46, height: 42)
            }
            .accessibilityLabel(viewModel.mapDisplayMode == .merchants
                                ? "Show communities" : "Show merchants")
        }
        .frame(width: 46)
        .modifier(GlassCapsuleBackground())
        .fixedSize()
    }

    private func toggleMapType() {
        let newType: MKMapType = (selectedMapType == .standard) ? .hybrid : .standard
        selectedMapTypeBinding.wrappedValue = newType
    }

    private func handleRecenterTap() {
        switch viewModel.locationManager.authorizationStatus {
        case .denied, .restricted:
            presentLocationSettingsAlert()
        case .notDetermined:
            requestAndCenterOnNextLocation()
        case .authorizedAlways, .authorizedWhenInUse:
            if viewModel.userLocation != nil {
                viewModel.centerMapToUserLocation()
            } else {
                requestAndCenterOnNextLocation()
            }
        @unknown default:
            requestAndCenterOnNextLocation()
        }
    }

    private func requestAndCenterOnNextLocation() {
        viewModel.locationManager.requestWhenInUseAuthorization()
        viewModel.isUpdatingLocation = true
        viewModel.locationManager.startUpdatingLocation()
        shouldCenterOnLocation = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            guard viewModel.isUpdatingLocation else { return }
            presentLocationTimeoutAlert()
            viewModel.locationManager.stopUpdatingLocation()
            viewModel.isUpdatingLocation = false
            shouldCenterOnLocation = false
        }
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
        if let windowScene = UIApplication.shared.connectedScenes
            .first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.topMostViewController()
                .present(alert, animated: true)
        }
    }

    private var mapTypeIcon: some View {
        ZStack {
            Image(systemName: "map.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .opacity(selectedMapType == .hybrid ? 1 : 0)
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .opacity(selectedMapType == .hybrid ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.16), value: selectedMapType == .hybrid)
    }

    private var mapModeIcon: some View {
        ZStack {
            Image(systemName: "person.3.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.accent)
                .opacity(viewModel.mapDisplayMode == .merchants ? 1 : 0)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.accent)
                .opacity(viewModel.mapDisplayMode == .merchants ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.16), value: viewModel.mapDisplayMode == .merchants)
    }
}

@available(iOS 17.0, *)
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

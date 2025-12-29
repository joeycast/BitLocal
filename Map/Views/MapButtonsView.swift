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
        VStack(spacing: 10) {
            
            Button(action: {
                let newType: MKMapType = (selectedMapType == .standard) ? .hybrid : .standard
                selectedMapTypeBinding.wrappedValue = newType
            }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .shadow(radius: 3)
                    Image(selectedMapType == .standard ? "globe-hemisphere-west-fill" : "map-trifold-fill")
                        .aboutIconStyle(size: 20, color: .white)
                }
            }
            
            
            // 🧭 Locate-me button - FIXED VERSION
            Button {
                switch viewModel.locationManager.authorizationStatus {
                case .denied, .restricted:
                    presentLocationSettingsAlert()
                case .notDetermined:
                    requestAndCenterOnNextLocation()
                case .authorizedAlways, .authorizedWhenInUse:
                    if viewModel.userLocation != nil {
                        // Use the new centerMapToUserLocation method that forces centering.
                        viewModel.centerMapToUserLocation()
                    } else {
                        requestAndCenterOnNextLocation()
                    }
                @unknown default:
                    requestAndCenterOnNextLocation()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .shadow(radius: 3)
                    Image("navigation-arrow-fill")
                        .aboutIconStyle(size: 20, color: .white)
                }
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
}

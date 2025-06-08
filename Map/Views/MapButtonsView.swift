//
//  MapButtonsView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import SwiftUI
import MapKit

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
                if let currentLoc = viewModel.userLocation {
                    // 1️⃣ FIXED: Use the new centerMapToUserLocation method that forces centering
                    viewModel.centerMapToUserLocation()
                    
                } else {
                    // 2️⃣ Otherwise, ask for permission and wait for onReceive to fire
                    viewModel.locationManager.requestWhenInUseAuthorization()
                    viewModel.isUpdatingLocation = true
                    viewModel.locationManager.startUpdatingLocation()
                    shouldCenterOnLocation = true
                    
                    // Optional: your existing timeout logic
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        guard viewModel.isUpdatingLocation else { return }
                        let alert = UIAlertController(
                            title: NSLocalizedString("location_alert_title", comment: ""),
                            message: nil,
                            preferredStyle: .alert
                        )
                        alert.addAction(.init(title: NSLocalizedString("ok_button", comment: ""),
                                              style: .default))
                        if let windowScene = UIApplication.shared.connectedScenes
                            .first as? UIWindowScene,
                           let rootVC = windowScene.windows.first?.rootViewController
                        {
                            rootVC.topMostViewController()
                                .present(alert, animated: true)
                        }
                        viewModel.locationManager.stopUpdatingLocation()
                        viewModel.isUpdatingLocation = false
                        shouldCenterOnLocation = false
                    }
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
}

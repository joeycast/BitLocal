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
            Button(action: {
                viewModel.locationManager.requestWhenInUseAuthorization()
                viewModel.isUpdatingLocation = true
                viewModel.locationManager.startUpdatingLocation()
                if let coordinate = userLocation?.coordinate {
                    viewModel.centerMap(to: coordinate)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if viewModel.isUpdatingLocation {
                        let alert = UIAlertController(
                            title: NSLocalizedString("location_alert_title", comment: "Alert title for failed location determination"),
                            message: nil,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: NSLocalizedString("ok_button", comment: "OK button"), style: .default))
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            rootViewController.topMostViewController().present(alert, animated: true, completion: nil)
                        }
                        viewModel.locationManager.stopUpdatingLocation()
                        viewModel.isUpdatingLocation = false
                    }
                }
            }) {
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
    }
}

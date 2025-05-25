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
                        .fill(Color.orange)
                        .frame(width: 44, height: 44)
                        .shadow(radius: 3)
                    Image(systemName: selectedMapType == .standard ? "globe.americas.fill" : "map.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
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
                            title: "Location could not be determined. Please check if location permissions have been granted.",
                            message: nil,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            rootViewController.topMostViewController().present(alert, animated: true, completion: nil)
                        }
                        viewModel.locationManager.stopUpdatingLocation()
                        viewModel.isUpdatingLocation = false
                    }
                }
            }) {
                Image(systemName: "location.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.white)
                    .padding()
                    .background(Circle().fill(Color.orange))
            }
            .shadow(radius: 3)
        }
    }
}

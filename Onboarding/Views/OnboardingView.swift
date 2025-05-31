//
//  OnboardingView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//

import SwiftUI
import CoreLocation

struct OnboardingPage {
    let titleKey: String
    let subtitleKey: String
    let image: String
    let bgColor: Color
    let isLocationPage: Bool
}

struct OnboardingView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    @Binding var didCompleteOnboarding: Bool
    @State private var currentPage = 0
    @State private var locationManager = CLLocationManager()
    @State private var locationDelegate = LocationPermissionDelegate()
    @State private var iconScale: CGFloat = 1.0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            titleKey: "onboarding_discover_title",
            subtitleKey: "onboarding_discover_subtitle",
            image: "currency-btc-bold",
            bgColor: .accentColor,
            isLocationPage: false
        ),
        OnboardingPage(
            titleKey: "onboarding_map_title",
            subtitleKey: "onboarding_map_subtitle",
            image: "map-trifold-fill",
            bgColor: .green,
            isLocationPage: false
        ),
        OnboardingPage(
            titleKey: "onboarding_location_title",
            subtitleKey: "onboarding_location_subtitle",
            image: "navigation-arrow-fill",
            bgColor: .blue,
            isLocationPage: true
        ),
        OnboardingPage(
            titleKey: "onboarding_ready_title",
            subtitleKey: "onboarding_ready_subtitle",
            image: "binoculars-fill",
            bgColor: .purple,
            isLocationPage: false
        )
    ]

    var body: some View {
        ZStack {
            // Background layers
            pages[currentPage].bgColor.ignoresSafeArea()
            Color(UIColor.systemBackground)
                .opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // Bouncing icon with smooth transition (prevents distortion)
                GeometryReader { geo in
                    ZStack {
                        // Keyed on currentPage to ensure a new view for each icon, enabling smooth transition
                        ZStack {
                            Circle()
                                .fill(pages[currentPage].bgColor)
                                .frame(width: 120, height: 120)
                                .shadow(color: pages[currentPage].bgColor.opacity(0.3), radius: 16, x: 0, y: 8)
                            Image(pages[currentPage].image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 68, height: 68)
                                .foregroundColor(.white)
                                .scaleEffect(iconScale)
                                .offset(y: pages[currentPage].image == "navigation-arrow-fill" ? 2 : 0)
                                .offset(x: pages[currentPage].image == "navigation-arrow-fill" ? -4 : 0)
                                .offset(x: pages[currentPage].image == "currency-btc-bold" ? 1 : 0)
                        }
                        .id(currentPage)
                        .animation(.easeInOut(duration: 0.5), value: currentPage)
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height * 1.0)
                }
                .frame(height: 200)

                // Title & subtitle
                VStack(spacing: 12) {
                    Text(LocalizedStringKey(pages[currentPage].titleKey))
                        .font(.largeTitle).bold()
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .id("title\(currentPage)")
                        .animation(.spring(), value: currentPage)

                    Text(LocalizedStringKey(pages[currentPage].subtitleKey))
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .id("subtitle\(currentPage)")
                        .animation(.spring(response: 0.6), value: currentPage)
                }
                .padding(.top, 50)

                Spacer()

                // 🔹 Indicator always visible
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage
                                  ? pages[currentPage].bgColor
                                  : Color.gray.opacity(0.3))
                            .frame(width: i == currentPage ? 32 : 12, height: 8)
                            .animation(.easeInOut(duration: 0.25), value: currentPage)
                    }
                }
                .padding(.bottom, 12)

                // 🔹 Page-specific controls
                if pages[currentPage].isLocationPage {
                    // Location permission UI
                    VStack(spacing: 16) {
                        Button {
                            requestLocationPermission()
                        } label: {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("onboarding_button_enable_location")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(pages[currentPage].bgColor)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(color: pages[currentPage].bgColor.opacity(0.3), radius: 4, x: 0, y: 2)
                        }

                        Button {
                            proceedToNextPage()
                        } label: {
                            Text("onboarding_button_location_skip")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 20)

                } else {
                    // Next / Get Started button
                    Button {
                        proceedToNextPage()
                    } label: {
                        Text(currentPage == pages.count - 1 ? "onboarding_button_get_started" : "onboarding_button_next")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(pages[currentPage].bgColor)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(color: pages[currentPage].bgColor.opacity(0.3), radius: 4, x: 0, y: 2)
                            .scaleEffect(currentPage == pages.count - 1 ? 1.05 : 1.0)
                            .animation(.spring(response: 0.4), value: currentPage)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 26)
                }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal)
            .onAppear {
                // Start bouncing
                withAnimation(
                    Animation.easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                ) {
                    iconScale = 1.08
                }
                locationManager.delegate = locationDelegate
            }
            .onChange(of: currentPage) {
                iconScale = 1.0
                withAnimation(
                    Animation.easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                ) {
                    iconScale = 1.08
                }
            }
            .animation(.easeInOut(duration: 0.4), value: currentPage)
        }
    }

    private func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        viewModel.locationManager.startUpdatingLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proceedToNextPage()
        }
    }

    private func proceedToNextPage() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            if currentPage < pages.count - 1 {
                currentPage += 1
            } else {
                didCompleteOnboarding = true
            }
        }
    }
}

// Delegate for location permission changes
class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        print("Location authorization status changed: \(status)")
    }
}

//
//  OnboardingView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//

import SwiftUI
import CoreLocation
import Foundation // for DebugUtils
import UIKit     // ← added, for checking userInterfaceIdiom

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

    // ──────────────── START: iPad‐Detection Helper ────────────────
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    // ──────────────── END: iPad‐Detection Helper ──────────────────

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
        GeometryReader { fullGeo in
            // Determine if we're on an iPad in landscape orientation
            let isLandscape = fullGeo.size.width > fullGeo.size.height
            let isPadLandscape = isPad && isLandscape

            ZStack {
                // Background layers (same for both)
                pages[currentPage].bgColor.ignoresSafeArea()
                Color(UIColor.systemBackground)
                    .opacity(0.95)
                    .ignoresSafeArea()

                VStack(spacing: isPadLandscape ? 40 : (isPad ? 40 : 28)) {
                    // Bouncing icon with smooth transition
                    GeometryReader { iconGeo in
                        ZStack {
                            // Keyed on currentPage for smooth transition
                            ZStack {
                                // Circle size: slightly smaller in pad-landscape
                                Circle()
                                    .fill(pages[currentPage].bgColor)
                                    .frame(
                                        width: isPadLandscape ? 140 : (isPad ? 180 : 120),
                                        height: isPadLandscape ? 140 : (isPad ? 180 : 120)
                                    )
                                    .shadow(
                                        color: pages[currentPage].bgColor.opacity(0.3),
                                        radius: isPadLandscape ? 16 : (isPad ? 24 : 16),
                                        x: 0,
                                        y: isPadLandscape ? 8 : (isPad ? 12 : 8)
                                    )

                                // Image size: slightly smaller in pad-landscape
                                Image(pages[currentPage].image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(
                                        width: isPadLandscape ? 80 : (isPad ? 100 : 68),
                                        height: isPadLandscape ? 80 : (isPad ? 100 : 68)
                                    )
                                    .foregroundColor(.white)
                                    .scaleEffect(iconScale)
                                    .offset(
                                        y: pages[currentPage].image == "navigation-arrow-fill" ? 2 : 0
                                    )
                                    .offset(
                                        x: pages[currentPage].image == "navigation-arrow-fill" ? -4 : 0
                                    )
                                    .offset(
                                        x: pages[currentPage].image == "currency-btc-bold" ? 1 : 0
                                    )
                            }
                            .id(currentPage)
                            .animation(.easeInOut(duration: 0.5), value: currentPage)
                        }
                        .position(
                            x: iconGeo.size.width / 2,
                            y: iconGeo.size.height * 1.0
                        )
                    }
                    .frame(height: isPadLandscape ? 220 : (isPad ? 300 : 200))

                    // Title & subtitle
                    VStack(spacing: isPadLandscape ? 12 : (isPad ? 16 : 12)) {
                        Text(LocalizedStringKey(pages[currentPage].titleKey))
                            .font(
                                isPadLandscape
                                    ? .system(size: 30, weight: .bold)
                                    : (isPad ? .system(size: 36, weight: .bold) : .largeTitle.bold())
                            )
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .id("title\(currentPage)")
                            .animation(.spring(), value: currentPage)

                        Text(LocalizedStringKey(pages[currentPage].subtitleKey))
                            .font(
                                isPadLandscape
                                    ? .title3
                                    : (isPad ? .title : .title3)
                            )
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, isPadLandscape ? 16 : (isPad ? 24 : 14))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .id("subtitle\(currentPage)")
                            .animation(.spring(response: 0.6), value: currentPage)
                    }
                    .padding(.top, isPadLandscape ? 50 : (isPad ? 80 : 50))

                    Spacer()

                    // Indicator
                    HStack(spacing: isPadLandscape ? 10 : (isPad ? 12 : 8)) {
                        ForEach(pages.indices, id: \.self) { i in
                            Capsule()
                                .fill(
                                    i == currentPage
                                        ? pages[currentPage].bgColor
                                        : Color.gray.opacity(0.3)
                                )
                                .frame(
                                    width: i == currentPage
                                        ? (isPadLandscape ? 32 : (isPad ? 40 : 32))
                                        : (isPadLandscape ? 12 : (isPad ? 16 : 12)),
                                    height: isPadLandscape ? 10 : (isPad ? 12 : 8)
                                )
                                .animation(.easeInOut(duration: 0.25), value: currentPage)
                        }
                    }
                    .padding(.bottom, isPadLandscape ? 16 : (isPad ? 20 : 12))

                    // Page-specific controls
                    if pages[currentPage].isLocationPage {
                        // Location permission UI
                        VStack(spacing: isPadLandscape ? 20 : (isPad ? 24 : 16)) {
                            Button {
                                requestLocationPermission()
                            } label: {
                                HStack {
                                    Image(systemName: "location.fill")
                                    Text("onboarding_button_enable_location")
                                }
                                .font(isPadLandscape ? .system(size: 20, weight: .semibold) : (isPad ? .system(size: 22, weight: .semibold) : .headline))
                                .frame(maxWidth: isPadLandscape ? 420 : (isPad ? 500 : 340))
                                .padding(.vertical, isPadLandscape ? 16 : (isPad ? 20 : 16))
                                .background(pages[currentPage].bgColor)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .shadow(
                                    color: pages[currentPage].bgColor.opacity(0.3),
                                    radius: isPadLandscape ? 4 : (isPad ? 6 : 4),
                                    x: 0,
                                    y: isPadLandscape ? 2 : (isPad ? 4 : 2)
                                )
                            }

                            Button {
                                proceedToNextPage()
                            } label: {
                                Text("onboarding_button_location_skip")
                                    .font(isPadLandscape ? .system(size: 16) : (isPad ? .system(size: 18) : .subheadline))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, isPadLandscape ? 12 : (isPad ? 16 : 6))
                        .padding(.bottom, isPadLandscape ? 20 : (isPad ? 30 : 20))

                    } else {
                        // Next / Get Started button
                        Button {
                            proceedToNextPage()
                        } label: {
                            Text(
                                currentPage == pages.count - 1
                                    ? "onboarding_button_get_started"
                                    : "onboarding_button_next"
                            )
                            .font(isPadLandscape ? .system(size: 20, weight: .semibold) : (isPad ? .system(size: 22, weight: .semibold) : .headline))
                            .frame(maxWidth: isPadLandscape ? 420 : (isPad ? 500 : 340))
                            .padding(.vertical, isPadLandscape ? 16 : (isPad ? 20 : 16))
                            .background(pages[currentPage].bgColor)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(
                                color: pages[currentPage].bgColor.opacity(0.3),
                                radius: isPadLandscape ? 4 : (isPad ? 6 : 4),
                                x: 0,
                                y: isPadLandscape ? 2 : (isPad ? 4 : 2)
                            )
                            .animation(.spring(response: 0.4), value: currentPage)
                        }
                        .padding(.horizontal, isPadLandscape ? 12 : (isPad ? 16 : 6))
                        .padding(.bottom, isPadLandscape ? 20 : (isPad ? 34 : 26))
                    }
                }
                .frame(maxWidth: isPad ? 600 : 460)
                .padding(.horizontal, isPadLandscape ? 16 : (isPad ? 32 : 0))
                .frame(width: fullGeo.size.width, height: fullGeo.size.height, alignment: .center)
            }
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
        Debug.log("Location authorization status changed: \(status)")
    }
}

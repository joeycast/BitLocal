//
//  OnboardingView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//

import SwiftUI
import CoreLocation

struct OnboardingPage {
    let title: String
    let subtitle: String
    let image: String // SF Symbol or asset name
    let bgColor: Color
    let isLocationPage: Bool
}

struct OnboardingView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    @Binding var didCompleteOnboarding: Bool
    @State private var currentPage = 0
    @State private var locationManager = CLLocationManager()
    @State private var locationDelegate = LocationPermissionDelegate()

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Discover BitLocal",
            subtitle: "Unlock a world of local shops and experiences that accept Bitcoin.",
            image: "bitcoinsign.circle.fill",
            bgColor: Color.orange,
            isLocationPage: false
        ),
        OnboardingPage(
            title: "Explore Seamlessly",
            subtitle: "Find businesses on the map, browse details, and plan your next adventure.",
            image: "map.fill",
            bgColor: Color.blue,
            isLocationPage: false
        ),
        OnboardingPage(
            title: "Enable Location Services",
            subtitle: "Allow location access to enhance your experience with personalized recommendations and nearby businesses. This is optional and can be enabled later.",
            image: "location.fill",
            bgColor: Color.purple,
            isLocationPage: true
        ),
        OnboardingPage(
            title: "Share & Connect",
            subtitle: "Suggest new places, leave feedback, and help grow the Bitcoin community.",
            image: "bubble.left.and.bubble.right.fill",
            bgColor: Color.green,
            isLocationPage: false
        ),
        OnboardingPage(
            title: "Your Bitcoin Journey Starts Here",
            subtitle: "Ready to explore? Tap below and dive in!",
            image: "sparkles",
            bgColor: Color.yellow,
            isLocationPage: false
        )
    ]

    var body: some View {
        ZStack {
            // Full opacity background that completely covers everything underneath
            pages[currentPage].bgColor.opacity(0.08)
                .ignoresSafeArea(.all)
            
            // Add a solid background layer to prevent any bleed-through
            Color(UIColor.systemBackground)
                .opacity(0.95)
                .ignoresSafeArea(.all)
            
            VStack(spacing: 28) {
                Spacer(minLength: 30)

                // Animated image/icon with bounce effect
                ZStack {
                    Circle()
                        .fill(pages[currentPage].bgColor.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .shadow(color: pages[currentPage].bgColor.opacity(0.3), radius: 16, x: 0, y: 8)
                    Image(systemName: pages[currentPage].image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 68, height: 68)
                        .foregroundColor(pages[currentPage].bgColor)
                        .scaleEffect(1.0 + 0.08 * sin(Double(currentPage) * 1.5))
                        .animation(.easeInOut(duration: 0.6), value: currentPage)
                        .shadow(radius: 4)
                }
                .padding(.top, 16)
                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                .animation(.easeInOut, value: currentPage)

                // Animated text transitions
                VStack(spacing: 12) {
                    Text(pages[currentPage].title)
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.primary)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .id("title\(currentPage)")
                        .animation(.spring(), value: currentPage)

                    Text(pages[currentPage].subtitle)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .id("subtitle\(currentPage)")
                        .animation(.spring(response: 0.6), value: currentPage)
                }
                .padding(.top, 10)

                Spacer()

                // Special content for location page
                if pages[currentPage].isLocationPage {
                    VStack(spacing: 16) {
                        Button(action: {
                            requestLocationPermission()
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("Enable Location")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(pages[currentPage].bgColor)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(color: pages[currentPage].bgColor.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        
                        Button(action: {
                            proceedToNextPage()
                        }) {
                            Text("Skip for Now")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 20)
                } else {
                    // Slick page indicator
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? pages[currentPage].bgColor : Color.gray.opacity(0.3))
                                .frame(width: i == currentPage ? 32 : 12, height: 8)
                                .animation(.easeInOut(duration: 0.25), value: currentPage)
                        }
                    }
                    .padding(.bottom, 12)

                    // Next/Get Started button with animation
                    Button(action: {
                        proceedToNextPage()
                    }) {
                        Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
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
        }
        .animation(.easeInOut(duration: 0.4), value: currentPage)
        .onAppear {
            locationManager.delegate = locationDelegate
        }
    }
    
    private func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        viewModel.locationManager.startUpdatingLocation()
        
        // Add a small delay to allow the permission dialog to appear and be handled
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

// Simple delegate to handle location permission
class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Handle authorization changes if needed
        print("Location authorization status changed: \(status)")
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        // This view is no longer used, but kept for reference if you want per-page customization
        EmptyView()
    }
}

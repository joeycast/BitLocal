//
//  RootView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//

import SwiftUI
import Foundation // for Debug logging

@available(iOS 17.0, *)
struct RootView: View {
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @EnvironmentObject var contentViewModel: ContentViewModel
    @State private var hasTriggeredInitialFetch = false // Prevent duplicate calls
    
    var body: some View {
        ZStack {
            ContentView()
                .environmentObject(contentViewModel)
            
            if !didCompleteOnboarding {
                OnboardingView()
                    .environmentObject(contentViewModel)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(999)
            }
        }
        .onAppear {
            Debug.log("RootView.onAppear called")
            Debug.log("didCompleteOnboarding = \(didCompleteOnboarding)")
            Debug.log("allElements.isEmpty = \(contentViewModel.allElements.isEmpty)")
            Debug.log("isLoading = \(contentViewModel.isLoading)")
            Debug.log("appState = \(contentViewModel.appState)")
            Debug.log("hasTriggeredInitialFetch = \(hasTriggeredInitialFetch)")
            
            // Only fetch if user already completed onboarding AND we haven't triggered initial fetch
            if didCompleteOnboarding,
               !hasTriggeredInitialFetch,
               contentViewModel.appState == .active,
               contentViewModel.allElements.isEmpty,
               !contentViewModel.isLoading {
                Debug.log("Calling fetchElements() from RootView.onAppear - initial load")
                hasTriggeredInitialFetch = true
                
                // Delay slightly to ensure view hierarchy is stable
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    contentViewModel.fetchElements()
                    contentViewModel.resolvePendingDeepLinkIfNeeded()
                }
            }
        }
        .onChange(of: didCompleteOnboarding) { _, completed in
            Debug.log("onboarding completion changed to: \(completed)")

            guard completed else { return }
            
            // 1️⃣ Center map if we already have location
            if let loc = contentViewModel.userLocation {
                Debug.log("Centering map to existing user location after onboarding")
                contentViewModel.centerMap(to: loc.coordinate)
            } else {
                Debug.log("No user location yet - requesting location after onboarding")
                contentViewModel.requestWhenInUseLocationPermission()
            }
            
            // 2️⃣ Then start loading your data (only if not already triggered)
            if !hasTriggeredInitialFetch,
               contentViewModel.appState == .active,
               contentViewModel.allElements.isEmpty,
               !contentViewModel.isLoading {
                Debug.log("Calling fetchElements() from onChange - post onboarding")
                hasTriggeredInitialFetch = true
                
                // Small delay to ensure map is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    contentViewModel.fetchElements()
                    contentViewModel.resolvePendingDeepLinkIfNeeded()
                }
            }
        }
        .onOpenURL { url in
            contentViewModel.handleIncomingURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            contentViewModel.handleIncomingUserActivity(activity)
        }
        .sheet(item: $contentViewModel.deepLinkUnavailableState) { state in
            DeepLinkUnavailableView(state: state)
                .environmentObject(contentViewModel)
        }
        .animation(.easeInOut(duration: 0.3), value: didCompleteOnboarding)
    }
}

@available(iOS 17.0, *)
private struct DeepLinkUnavailableView: View {
    let state: DeepLinkUnavailableState
    @EnvironmentObject private var contentViewModel: ContentViewModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "mappin.slash.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)

                Text(state.title)
                    .font(.title2.weight(.semibold))

                Text(state.message)
                    .foregroundStyle(.secondary)

                Text("Place ID: \(state.placeID)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button("Retry") {
                    contentViewModel.retryDeepLinkUnavailablePlaceLookup()
                }
                .buttonStyle(.borderedProminent)

                Button("Search Nearby") {
                    contentViewModel.searchNearbyFromDeepLinkUnavailable()
                }
                .buttonStyle(.bordered)

                Button("Open Map") {
                    contentViewModel.openMapHomeFromDeepLinkUnavailable()
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Place unavailable")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

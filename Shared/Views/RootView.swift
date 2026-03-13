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
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
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

            triggerInitialFetchIfNeeded(source: "RootView.onAppear")
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

            // If onboarding warmup already finished, deep links can now resolve immediately.
            contentViewModel.resolvePendingDeepLinkIfNeeded()

            // 2️⃣ If warmup never started, kick off the normal initial fetch now.
            triggerInitialFetchIfNeeded(source: "RootView.didCompleteOnboarding")
        }
        .onChange(of: contentViewModel.appState) { _, newState in
            guard newState == .active else { return }
            triggerInitialFetchIfNeeded(source: "RootView.appStateActive")
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
        .onChange(of: merchantAlertsManager.activeDigest?.id) { _, _ in
            guard let digest = merchantAlertsManager.activeDigest else { return }
            contentViewModel.activateMerchantAlertDigest(digest)
        }
        .animation(.easeInOut(duration: 0.3), value: didCompleteOnboarding)
    }

    private func triggerInitialFetchIfNeeded(source: String) {
        guard !hasTriggeredInitialFetch else { return }
        guard contentViewModel.appState == .active else { return }
        guard contentViewModel.allElements.isEmpty else { return }
        guard !contentViewModel.isLoading else { return }

        let warmupOnly = !didCompleteOnboarding
        Debug.log("Calling fetchElements() from \(source) - warmupOnly=\(warmupOnly)")
        hasTriggeredInitialFetch = true

        let delay = warmupOnly ? 0.1 : 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            contentViewModel.fetchElements(warmupOnly: warmupOnly) {
                if contentViewModel.allElements.isEmpty {
                    Debug.log("Initial fetch from \(source) produced no data; allowing retry")
                    hasTriggeredInitialFetch = false
                }
            }
            if !warmupOnly {
                contentViewModel.resolvePendingDeepLinkIfNeeded()
            }
        }
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

//
//  RootView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//

import SwiftUI
import Foundation // for Debug logging

struct RootView: View {
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @EnvironmentObject var contentViewModel: ContentViewModel
    @Environment(MerchantAlertsManager.self) private var merchantAlertsManager
    @State private var featureHintsController = FeatureHintsController()
    @State private var releaseNotesController = ReleaseNotesController()
    @State private var hasTriggeredInitialFetch = false // Prevent duplicate calls
    @State private var deferredInitialFetchTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            ContentView()
                .environmentObject(contentViewModel)
                .environment(featureHintsController)
                .environment(releaseNotesController)
            
            if !didCompleteOnboarding {
                OnboardingView()
                    .environmentObject(contentViewModel)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
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

            featureHintsController.installOverlayWindow()
            triggerInitialFetchIfNeeded(source: "RootView.onAppear")
            evaluateReleaseNotesPresentation()
            evaluateFeatureHintsPresentation()
        }
        .onChange(of: didCompleteOnboarding) { _, completed in
            Debug.log("onboarding completion changed to: \(completed)")

            guard completed else { return }
            Debug.logTiming("onboarding", "didCompleteOnboarding flipped to true")

            contentViewModel.preparePostOnboardingPresentation()

            // If onboarding warmup already finished, deep links can now resolve immediately.
            contentViewModel.resolvePendingDeepLinkIfNeeded()

            // 2️⃣ If warmup never started, kick off the normal initial fetch now.
            triggerInitialFetchIfNeeded(source: "RootView.didCompleteOnboarding")
            evaluateReleaseNotesPresentation()
            evaluateFeatureHintsPresentation()
        }
        .onChange(of: contentViewModel.appState) { _, newState in
            guard newState == .active else { return }
            triggerInitialFetchIfNeeded(source: "RootView.appStateActive")
            evaluateReleaseNotesPresentation()
            evaluateFeatureHintsPresentation()
        }
        .onChange(of: contentViewModel.isReadyForPostOnboardingPresentation) { _, _ in
            Debug.logTiming(
                "onboarding",
                "main UI readiness changed -> ready=\(contentViewModel.isReadyForPostOnboardingPresentation), loaded=\(contentViewModel.hasLoadedInitialData), allElements=\(contentViewModel.allElements.count), visibleElements=\(contentViewModel.visibleElements.count), forceMapRefresh=\(contentViewModel.forceMapRefresh)"
            )
            evaluateReleaseNotesPresentation()
            evaluateFeatureHintsPresentation()
        }
        .onChange(of: contentViewModel.hasLoadedInitialData) { _, loaded in
            Debug.logTiming(
                "data",
                "hasLoadedInitialData changed -> \(loaded), allElements=\(contentViewModel.allElements.count), appState=\(contentViewModel.appState)"
            )
        }
        .onChange(of: featureHintsController.replayRequestCount) { _, _ in
            evaluateFeatureHintsPresentation()
        }
        .onChange(of: featureHintsController.mainUIPresentationCount) { _, _ in
            evaluateFeatureHintsPresentation()
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
        .sheet(item: $releaseNotesController.activeReleaseNotes) { entry in
            ReleaseNotesSheetView(entry: entry) {
                releaseNotesController.dismiss()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: merchantAlertsManager.activeDigest?.id) { _, _ in
            guard let digest = merchantAlertsManager.activeDigest else { return }
            contentViewModel.activateMerchantAlertDigest(digest)
        }
        .animation(
            BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion),
            value: didCompleteOnboarding
        )
        .onDisappear {
            deferredInitialFetchTask?.cancel()
            deferredInitialFetchTask = nil
        }
    }

    private func triggerInitialFetchIfNeeded(source: String) {
        guard !hasTriggeredInitialFetch else { return }
        guard contentViewModel.appState == .active else { return }
        guard contentViewModel.allElements.isEmpty else { return }
        guard !contentViewModel.isLoading else { return }

        let warmupOnly = !didCompleteOnboarding
        Debug.log("Calling fetchElements() from \(source) - warmupOnly=\(warmupOnly)")
        Debug.logTiming("data", "triggerInitialFetchIfNeeded source=\(source) warmupOnly=\(warmupOnly)")
        hasTriggeredInitialFetch = true

        let delay = warmupOnly ? 0.1 : 0.2
        deferredInitialFetchTask?.cancel()
        deferredInitialFetchTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
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

    private func evaluateFeatureHintsPresentation() {
        guard !releaseNotesController.isPresenting else { return }
        featureHintsController.evaluatePresentation(
            didCompleteOnboarding: didCompleteOnboarding,
            isReadyForMainUI: contentViewModel.isReadyForPostOnboardingPresentation
        )
    }

    private func evaluateReleaseNotesPresentation() {
        releaseNotesController.evaluatePresentation(
            didCompleteOnboarding: didCompleteOnboarding,
            isReadyForMainUI: contentViewModel.isReadyForPostOnboardingPresentation
        )
    }
}

private struct DeepLinkUnavailableView: View {
    let state: DeepLinkUnavailableState
    @EnvironmentObject private var contentViewModel: ContentViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                ContentUnavailableView {
                    Label(state.title, systemImage: "mappin.slash.circle.fill")
                } description: {
                    VStack(spacing: 8) {
                        Text(state.message)
                        Text(
                            "Place ID: \(state.placeID)",
                            comment: "Deep link unavailable detail showing the place identifier"
                        )
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                    }
                } actions: {
                    VStack(spacing: 12) {
                        Button("Retry", action: contentViewModel.retryDeepLinkUnavailablePlaceLookup)
                            .buttonStyle(.borderedProminent)

                        Button("Search Nearby", action: contentViewModel.searchNearbyFromDeepLinkUnavailable)
                            .buttonStyle(.bordered)

                        Button("Open Map", action: contentViewModel.openMapHomeFromDeepLinkUnavailable)
                            .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Place unavailable")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

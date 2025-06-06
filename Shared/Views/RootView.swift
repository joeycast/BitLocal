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
            
            // If user already completed onboarding previously, kick off fetch
            if didCompleteOnboarding,
               contentViewModel.allElements.isEmpty,
               !contentViewModel.isLoading {
                Debug.log("Calling fetchElements() from RootView.onAppear")
                contentViewModel.fetchElements()
            }
        }
        .onChange(of: didCompleteOnboarding) { _, completed in
            Debug.log("onboarding completion changed to: \(completed)")

            guard completed else { return }
            
            // 1️⃣ Center map if we already have location
            if let loc = contentViewModel.userLocation {
                contentViewModel.centerMap(to: loc.coordinate)
            }
            
            // 2️⃣ Then start loading your data
            if contentViewModel.allElements.isEmpty,
               !contentViewModel.isLoading {
                Debug.log("Calling fetchElements() from onChange")
                contentViewModel.fetchElements()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: didCompleteOnboarding)
    }
}

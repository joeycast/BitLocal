//
//  RootView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//

import SwiftUI

@available(iOS 17.0, *)
struct RootView: View {
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @EnvironmentObject var contentViewModel: ContentViewModel
    
    var body: some View {
        ZStack {
            ContentView()
                .environmentObject(contentViewModel)
            
            if !didCompleteOnboarding {
                OnboardingView(didCompleteOnboarding: $didCompleteOnboarding)
                    .environmentObject(contentViewModel)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(999)
            }
        }
        .onAppear {
            // If user already completed onboarding previously, kick off fetch
            if didCompleteOnboarding,
               contentViewModel.allElements.isEmpty,
               !contentViewModel.isLoading {
                contentViewModel.fetchElements()
            }
        }
        .onChange(of: didCompleteOnboarding) { completed in
            guard completed else { return }
            
            // 1️⃣ Center map if we already have location
            if let loc = contentViewModel.userLocation {
                contentViewModel.centerMap(to: loc.coordinate)
            }
            
            // 2️⃣ Then start loading your data
            if contentViewModel.allElements.isEmpty,
               !contentViewModel.isLoading {
                contentViewModel.fetchElements()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: didCompleteOnboarding)
    }
}

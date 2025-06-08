//
//  bitlocalApp.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 4/6/25.
//

import SwiftUI
import Foundation // for Debug logging

@main
@available(iOS 17.0, *)
struct bitlocalApp: App {

    // Add the environment property to track the app's scene phase
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var contentViewModel = ContentViewModel()
    
    // Track scene phase timing to avoid false triggers
    @State private var lastActiveTime: Date = Date()
    @State private var lastBackgroundTime: Date?
    @State private var scenePhaseChangeTimer: Timer?
    
    init() {
        MyFont.registerFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(contentViewModel)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    Debug.log("scenePhase changed from \(oldPhase) to: \(newPhase)")
                    
                    // Cancel any pending timer
                    scenePhaseChangeTimer?.invalidate()
                    scenePhaseChangeTimer = nil
                    
                    // Batch state changes to minimize UI updates
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            handleActiveState(from: oldPhase)
            
        case .inactive:
            Debug.log("Scene became inactive")
            // Don't immediately update - batch with potential background state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Only update if we're still inactive (haven't moved to background)
                if self.scenePhase == .inactive {
                    self.contentViewModel.handleAppBecameInactive()
                }
            }
            
        case .background:
            Debug.log("Scene entered background")
            lastBackgroundTime = Date()
            // Update state immediately since we know we're backgrounded
            contentViewModel.handleAppEnteredBackground()
            
        @unknown default:
            Debug.log("Unknown scene phase: \(newPhase)")
        }
    }
    
    private func handleActiveState(from oldPhase: ScenePhase) {
        let now = Date()
        
        // Calculate time since last background (if any)
        let timeSinceBackground = lastBackgroundTime?.timeIntervalSince(now) ?? 0
        let backgroundDuration = abs(timeSinceBackground)
        
        // Calculate time since last active
        let timeSinceLastActive = now.timeIntervalSince(lastActiveTime)
        
        Debug.log("Scene became active - from: \(oldPhase)")
        Debug.log("Time since last active: \(timeSinceLastActive)s")
        Debug.log("Background duration: \(backgroundDuration)s")
        
        lastActiveTime = now
        
        // Always update to active state first
        contentViewModel.handleAppBecameActive()
        
        // But debounce fetching behavior for rapid transitions
        if timeSinceLastActive < 2.0 {
            Debug.log("Rapid active transition detected - skipping fetch")
            return
        }
        
        // Only fetch if coming from meaningful background time
        let shouldFetch = shouldFetchOnActive(
            fromPhase: oldPhase,
            backgroundDuration: backgroundDuration,
            timeSinceLastActive: timeSinceLastActive
        )
        
        if shouldFetch {
            Debug.log("Scheduling additional fetchElements() - meaningful app return")
            
            // Small delay to let UI settle, especially after true app return
            scenePhaseChangeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                DispatchQueue.main.async {
                    // Only fetch if still active
                    if self.contentViewModel.appState == .active {
                        self.contentViewModel.fetchElements()
                    }
                }
            }
        } else {
            Debug.log("Skipping additional fetchElements() - not a meaningful app return")
        }
    }
    
    private func shouldFetchOnActive(
        fromPhase: ScenePhase,
        backgroundDuration: TimeInterval,
        timeSinceLastActive: TimeInterval
    ) -> Bool {
        
        // Don't fetch if transitioning from inactive (likely rapid transition)
        if fromPhase == .inactive && backgroundDuration < 5.0 {
            Debug.log("Not fetching: rapid inactive→active transition")
            return false
        }
        
        // Don't fetch if we were active very recently (simulator glitch)
        if timeSinceLastActive < 10.0 {
            Debug.log("Not fetching: was active recently (\(timeSinceLastActive)s ago)")
            return false
        }
        
        // Fetch if coming from background and it's been a while
        if fromPhase == .background && backgroundDuration > 30.0 {
            Debug.log("Fetching: returning from background after \(backgroundDuration)s")
            return true
        }
        
        // Fetch if it's been more than 5 minutes since last active
        if timeSinceLastActive > 300.0 {
            Debug.log("Fetching: been inactive for \(timeSinceLastActive)s")
            return true
        }
        
        Debug.log("Not fetching: conditions not met")
        return false
    }
}

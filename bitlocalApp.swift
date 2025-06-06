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
    
    init() {
        MyFont.registerFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(contentViewModel)
                .onChange(of: scenePhase) { _, newPhase in
                    Debug.log("scenePhase changed to: \(newPhase)")
                    if newPhase == .active {
                        Debug.log("Scene became active, calling fetchElements()")
                        contentViewModel.fetchElements()
                    }
                }
        }
    }
}

//
//  bitlocalApp.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 4/6/25.
//

import SwiftUI

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
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        contentViewModel.fetchElements()
                    }
                }
        }
    }
}

//
//  AppearanceManager.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/25/25.
//


// AppearanceManager.swift
import SwiftUI

class AppearanceManager: ObservableObject {
    @Published var appearance: Appearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
        }
    }
    
    init() {
        let storedValue = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        self.appearance = Appearance(rawValue: storedValue) ?? .system
    }
}
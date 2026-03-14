// CustomFonts.swift

import SwiftUI
import Foundation // for Debug logging

public struct MyFont {
    public static func registerFonts() {
        registerFont(bundle: Bundle.main, fontName: "Fredoka-Medium", fontExtension: "ttf")
    }
    
    fileprivate static func registerFont(bundle: Bundle, fontName: String, fontExtension: String) {
        guard let fontURL = bundle.url(forResource: fontName, withExtension: fontExtension) else {
            fatalError("Couldn't locate font file")
        }
        
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
        if !registered, let error = error {
            Debug.log("Failed to register font: \(error.takeRetainedValue().localizedDescription)")
        }
    }
}

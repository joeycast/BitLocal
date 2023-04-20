// CustomFonts.swift

import SwiftUI

public struct MyFont {
    public static func registerFonts() {
        registerFont(bundle: Bundle.main, fontName: "Ubuntu-LightItalic", fontExtension: "ttf")
        registerFont(bundle: Bundle.main, fontName: "Ubuntu-MediumItalic", fontExtension: "ttf")
    }
    
    fileprivate static func registerFont(bundle: Bundle, fontName: String, fontExtension: String) {
        guard let fontURL = bundle.url(forResource: fontName, withExtension: fontExtension),
              let fontDataProvider = CGDataProvider(url: fontURL as CFURL),
              let font = CGFont(fontDataProvider) else {
            fatalError("Couldn't create font from data")
        }
        
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterGraphicsFont(font, &error)
        if let error = error {
            print("Failed to register font: \(error.takeRetainedValue().localizedDescription)")
        }
    }
}

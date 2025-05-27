//
//  InfoButtonView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI

struct InfoButtonView: View {
    @Binding var showingAbout: Bool

    var body: some View {
        Button(action: {
            showingAbout = true
        }) {
            Image("info-fill")
                .aboutIconStyle(size: 18)
        }
        .accessibilityLabel(Text("about_accessibility_label"))
    }
}

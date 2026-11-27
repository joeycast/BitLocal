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
        Button("about_accessibility_label", systemImage: "info.circle.fill") {
            showingAbout = true
        }
        .labelStyle(.iconOnly)
        .font(.body)
        .foregroundStyle(.accent)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }
}

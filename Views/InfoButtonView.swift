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
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundColor(.orange)
                .background(
                    Circle()
                        .fill(Color(.systemBackground).opacity(0.8))
                )
        }
        .accessibilityLabel("About")
    }
}

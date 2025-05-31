//
//  LoadingScreenView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//


import SwiftUI

struct LoadingScreenView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ProgressView("loading_title") // Localized
                .progressViewStyle(.circular)
                .font(.title2)
                .padding(.bottom, 16)
            Text("loading_subtitle") // Localized
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
}

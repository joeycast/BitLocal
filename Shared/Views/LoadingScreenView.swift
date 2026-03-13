//
//  LoadingScreenView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//


import SwiftUI

struct LoadingScreenView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.secondary)
                .scaleEffect(0.9)
            Text("loading_title") // Localized
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("loading_subtitle") // Localized
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

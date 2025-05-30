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
            ProgressView("Loading businesses…")
                .progressViewStyle(.circular)
                .font(.title2)
                .padding(.bottom, 16)
            Text("Hang tight! We’re fetching all the best Bitcoin spots near you.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
}

//
//  OpenStreetMapAttributionView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI

struct OpenStreetMapAttributionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) var colorScheme
    @State private var isFaded = false

    var body: some View {
        Button(action: {
            if let url = URL(string: "https://www.openstreetmap.org/copyright") {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 0) {
                Text("osm_attribution_prefix")
                    .font(.system(size: 10))
                    .foregroundColor(colorScheme == .light ? .black : .white)
                Text("osm_openstreetmap")
                    .font(.system(size: 10))
                    .underline()
                    .foregroundColor(colorScheme == .light ? .black : .white)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
        .background(Color(colorScheme == .light ? UIColor.white : UIColor.black).opacity(colorScheme == .light ? 0.6 : 0.4))
        .cornerRadius(3)
        .opacity(isFaded ? 0 : 1)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                withAnimation(.easeInOut(duration: 3)) {
                    isFaded = true
                }
            }
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .active {
                withAnimation(.easeInOut(duration: 0)) {
                    isFaded = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    withAnimation(.easeInOut(duration: 3)) {
                        isFaded = true
                    }
                }
            }
        }
    }
}

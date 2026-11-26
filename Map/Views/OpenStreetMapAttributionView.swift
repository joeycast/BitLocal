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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFaded = false
    @State private var fadeWorkItem: DispatchWorkItem?

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
        .buttonStyle(.tactilePress(scale: 0.96))
        .padding(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
        .background(Color(colorScheme == .light ? UIColor.white : UIColor.black).opacity(colorScheme == .light ? 0.6 : 0.4))
        .cornerRadius(3)
        .opacity(isFaded ? 0 : 1)
        .onAppear {
            scheduleFade()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .active {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isFaded = false
                }
                scheduleFade()
            }
        }
        .onDisappear {
            fadeWorkItem?.cancel()
            fadeWorkItem = nil
        }
    }

    private func scheduleFade() {
        fadeWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(
                BitLocalMotion.animation(.easeOut(duration: 0.6), reduceMotion: reduceMotion)
            ) {
                isFaded = true
            }
        }
        fadeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }
}

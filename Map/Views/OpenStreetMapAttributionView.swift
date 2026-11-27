//
//  OpenStreetMapAttributionView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI

struct OpenStreetMapAttributionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var isFaded = false
    @State private var fadeTrigger = 0

    private static let osmCopyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!

    var body: some View {
        Button {
            openURL(Self.osmCopyrightURL)
        } label: {
            Text("\(Text("osm_attribution_prefix"))\(Text("osm_openstreetmap").underline())")
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(.regularMaterial, in: .rect(cornerRadius: 3))
                .frame(minWidth: 44, minHeight: 44, alignment: .bottomLeading)
                .contentShape(.rect)
        }
        .buttonStyle(.tactilePress(scale: 0.96))
        .opacity(isFaded ? 0 : 1)
        .allowsHitTesting(!isFaded)
        .task(id: fadeTrigger) {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            withAnimation(
                BitLocalMotion.animation(.easeOut(duration: 0.6), reduceMotion: reduceMotion)
            ) {
                isFaded = true
            }
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .active {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isFaded = false
                }
                fadeTrigger += 1
            }
        }
    }
}

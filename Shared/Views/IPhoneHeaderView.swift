//
//  IPhoneHeaderView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import SwiftUI
import MapKit

@available(iOS 17.0, *)
struct IPhoneHeaderView: View {
    let screenWidth: CGFloat
    @ObservedObject var viewModel: ContentViewModel
    @Binding var showingAbout: Bool
    @Binding var showingSettings: Bool
    var selectedMapTypeBinding: Binding<MKMapType>

    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    @State private var settingsButtonFrame: CGRect = .zero

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let height = geometry.size.height * 0.15
                Rectangle()
                    .cornerRadius(10)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .opacity(1)
                    .frame(width: screenWidth, height: height)
                    .padding(.top, -10)
                    .ignoresSafeArea()
                    .onAppear {
                        DispatchQueue.main.async {
                            viewModel.topPadding = height
                        }
                    }
            }
            VStack(alignment: .leading) {
                HStack {
                    InfoButtonView(showingAbout: $showingAbout)
                        .frame(maxWidth: 1, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing)
                        .padding(.leading, 25)
                    Spacer()
                    HStack(spacing: 0) {
                        Text(" bit")
                            .font(.custom("Ubuntu-LightItalic", size: 28))
                            .foregroundColor(.orange)
                        Text("local ")
                            .font(.custom("Ubuntu-MediumItalic", size: 28))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    SettingsButtonView(
                        selectedMapType: selectedMapTypeBinding,
                        appearance: $appearance,
                        distanceUnit: $distanceUnit,
                        onSettingsSelected: { showingSettings = true },
                        onButtonFrameChange: { frame in
                            settingsButtonFrame = frame
                        }
                    )
                    .padding(.leading, 5)
                    .allowsHitTesting(true)
                    .opacity(1)
                }
                .padding(.horizontal)
                .frame(height: 1)
                Spacer()
            }
            .padding(.top, 20)
        }
        .overlay(alignment: .topLeading) {
            if showingSettings {
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showingSettings = false } }
                CompactSettingsPopoverView(
                    selectedMapType: selectedMapTypeBinding,
                    onDone: { withAnimation { showingSettings = false } }
                )
                .position(x: settingsButtonFrame.maxX - 130, y: settingsButtonFrame.maxY + 115)
                .transition(.scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65, blendDuration: 0.25), value: showingSettings)
    }
}

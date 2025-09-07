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
    
    // Use environment object for instant updates
    @EnvironmentObject var appearanceManager: AppearanceManager
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    
    private var appearance: Appearance { appearanceManager.appearance }

    @State private var settingsButtonFrame: CGRect = .zero

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let height = geometry.size.height * 0.15
                Group {
                    if #available(iOS 26.0, *) {
                        Rectangle()
                            .fill(.thinMaterial)
                    } else {
                        Rectangle()
                    }
                }
                .cornerRadius(10)
                .foregroundColor(backgroundColorForCurrentScheme)
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
                        .padding(.leading)
                    Spacer()
                    Text("bitlocal")
                        .font(.custom("Fredoka-Medium", size: 28))
                        .foregroundColor(.accentColor)
                    Spacer()
                    SettingsButtonView(
                        selectedMapType: selectedMapTypeBinding,
                        appearance: $appearanceManager.appearance, // Bind to the environment object
                        distanceUnit: $distanceUnit,
                        onSettingsSelected: { showingSettings = true },
                        onButtonFrameChange: { frame in
                            settingsButtonFrame = frame
                        }
                    )
                    .padding(.trailing)
                    .allowsHitTesting(true)
                    .opacity(1)
                }
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
                .position(x: settingsButtonFrame.maxX - 120, y: settingsButtonFrame.maxY + 125)
                .transition(.scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65, blendDuration: 0.25), value: showingSettings)
    }
    
    private var backgroundColorForCurrentScheme: Color {
        let isDark: Bool
        switch appearance {
        case .system:
            isDark = systemColorScheme == .dark
        case .light:
            isDark = false
        case .dark:
            isDark = true
        }
        
        return isDark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color.white
    }
}

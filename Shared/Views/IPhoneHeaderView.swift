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
    private let headerControlWidth: CGFloat = 46
    private let headerControlHeight: CGFloat = 32
    private let headerHorizontalInset: CGFloat = 18

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
    @State private var showingMerchantAlerts = false

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let hasNotch = safeTop >= 40
            let contentTopPad: CGFloat = hasNotch ? 2 : 6
            let contentBottomPad: CGFloat = 6
            let totalHeight = safeTop + contentTopPad + headerControlHeight + contentBottomPad

            VStack(spacing: 0) {
                HStack {
                    InfoButtonView(showingAbout: $showingAbout)
                        .frame(width: headerControlWidth, height: headerControlHeight)
                    Spacer()
                    Text("bitlocal")
                        .font(.custom("Fredoka-Medium", size: headerTitleSize))
                        .foregroundColor(.accentColor)
                    Spacer()
                    SettingsButtonView(
                        selectedMapType: selectedMapTypeBinding,
                        appearance: $appearanceManager.appearance,
                        distanceUnit: $distanceUnit,
                        onSettingsSelected: { showingSettings = true },
                        onButtonFrameChange: { frame in
                            settingsButtonFrame = frame
                        }
                    )
                    .frame(width: headerControlWidth, height: headerControlHeight)
                }
                .padding(.horizontal, headerHorizontalInset)
                .padding(.top, contentTopPad)
                .padding(.bottom, contentBottomPad)
            }
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        Rectangle()
                            .fill(.thinMaterial)
                    } else {
                        backgroundColorForCurrentScheme
                    }
                }
                .cornerRadius(10)
                .ignoresSafeArea(edges: .top)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                viewModel.topPadding = totalHeight
            }
            .onChange(of: totalHeight) { _, newHeight in
                viewModel.topPadding = newHeight
            }
            .preference(key: HeaderHeightKey.self, value: totalHeight)
        }
        .overlay(alignment: .topLeading) {
            if showingSettings {
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showingSettings = false } }
                CompactSettingsPopoverView(
                    selectedMapType: selectedMapTypeBinding,
                    onDone: { withAnimation { showingSettings = false } },
                    onMerchantAlertsSelected: {
                        withAnimation { showingSettings = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showingMerchantAlerts = true
                        }
                    }
                )
                .position(x: settingsButtonFrame.maxX - 120, y: settingsButtonFrame.maxY + 125)
                .transition(.scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .fullScreenCover(isPresented: $showingMerchantAlerts) {
            MerchantAlertsView()
                .environmentObject(MerchantAlertsManager.shared)
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

    private var headerTitleSize: CGFloat {
        min(max(screenWidth * 0.065, 22), 28)
    }
}

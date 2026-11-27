//
//  IPhoneHeaderView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

import SwiftUI

struct IPhoneHeaderView: View {
    private let headerControlWidth: CGFloat = 46
    private let headerControlHeight: CGFloat = 44
    private let headerHorizontalInset: CGFloat = 18

    let screenWidth: CGFloat
    var viewModel: ContentViewModel
    @Binding var showingSettings: Bool

    // Use environment object for instant updates
    @Environment(AppearanceManager.self) private var appearanceManager
    @Environment(\.colorScheme) private var systemColorScheme

    private var appearance: Appearance { appearanceManager.appearance }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let hasNotch = safeTop >= 40
            let contentTopPad: CGFloat = hasNotch ? 2 : 6
            let contentBottomPad: CGFloat = 6
            let totalHeight = safeTop + contentTopPad + headerControlHeight + contentBottomPad

            VStack(spacing: 0) {
                HStack {
                    Color.clear
                        .frame(width: headerControlWidth, height: headerControlHeight)
                        .accessibilityHidden(true)
                    Spacer()
                    Text("bitlocal")
                        .font(.custom("Fredoka-Medium", size: headerTitleSize, relativeTo: .title2))
                        .foregroundStyle(.accent)
                    Spacer()
                    SettingsButtonView(
                        onSettingsSelected: { showingSettings = true }
                    )
                    .frame(width: headerControlWidth, height: headerControlHeight)
                }
                .padding(.horizontal, headerHorizontalInset)
                .padding(.top, contentTopPad)
                .padding(.bottom, contentBottomPad)
            }
            .frame(maxWidth: .infinity)
            .background {
                Group {
                    if #available(iOS 26.0, *) {
                        Rectangle()
                            .fill(.thinMaterial)
                    } else {
                        backgroundColorForCurrentScheme
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .ignoresSafeArea(edges: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                viewModel.topPadding = totalHeight
            }
            .onChange(of: totalHeight) { _, newHeight in
                viewModel.topPadding = newHeight
            }
            .preference(key: HeaderHeightKey.self, value: totalHeight)
        }
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

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

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let contentTopPad: CGFloat = safeTop >= 40 ? 2 : 6

            HStack {
                Spacer()
                SettingsButtonView(
                    onSettingsSelected: { showingSettings = true }
                )
                .frame(width: headerControlWidth, height: headerControlHeight)
            }
            .padding(.horizontal, headerHorizontalInset)
            .padding(.top, contentTopPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .onAppear {
                viewModel.topPadding = safeTop
            }
            .onChange(of: safeTop) { _, newSafeTop in
                viewModel.topPadding = newSafeTop
            }
            .preference(key: HeaderHeightKey.self, value: safeTop)
        }
    }
}

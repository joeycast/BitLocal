//
//  CustomiPadNavigationStackTitleView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI

struct CustomiPadNavigationStackTitleView: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("bitlocal")
                .font(.custom("Fredoka-Medium", size: 32))
                .foregroundColor(.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(x: -8)
    }
}

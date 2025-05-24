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
                    SettingsButtonView(selectedMapType: selectedMapTypeBinding)
                        .frame(maxWidth: 1, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 5)
                        .allowsHitTesting(true)
                        .opacity(1)
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
                    InfoButtonView(showingAbout: $showingAbout)
                        .frame(maxWidth: 1, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 2)
                        .padding(.leading, 7)
                }
                .padding(.horizontal)
                .frame(height: 1)
                Spacer()
            }
            .padding(.top, 20)
        }
    }
}

//
//  SplashScreenView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 6/3/25.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var playAnimation = true
    @State private var showMainView = false

    var body: some View {
        ZStack {
            if showMainView {
                ContentView() // Replace with your actual root view
            } else {
                LottieView(name: "splash_screen", play: $playAnimation)
                    .ignoresSafeArea()
                    .onChange(of: playAnimation) { finished in
                        if !finished {
                            withAnimation {
                                showMainView = true
                            }
                        }
                    }
            }
        }
    }
}

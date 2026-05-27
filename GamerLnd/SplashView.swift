// SplashView.swift
// Lightweight in-app splash to cover cold start before ContentView loads.

import SwiftUI

struct SplashView: View {
    var message: String = "Loading GamerLnd..."

    var body: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                if let _ = UIImage(named: "icon") {
                    Image("icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Text("GamerLnd")
                        .font(.title.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                }

                ProgressView()
                    .tint(ColorTheme.accent)

                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(ColorTheme.subtext)
            }
            .padding(.horizontal, 20)
        }
    }
}


// OnboardingView.swift
// Simple onboarding flow before login.

import SwiftUI

struct OnboardingView: View {
    struct Page: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let systemImage: String
    }

    let onDone: () -> Void

    @State private var index: Int = 0

    private let pages: [Page] = [
        Page(title: "Log What You Play",
             subtitle: "Track games, rate them, and build your library.",
             systemImage: "gamecontroller.fill"),
        Page(title: "Share Your Thoughts",
             subtitle: "Write reviews and see what your friends think.",
             systemImage: "text.quote"),
        Page(title: "Build Lists",
             subtitle: "Ranked, tiered, or collections — make it yours.",
             systemImage: "list.bullet.rectangle")
    ]

    var body: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 20)

                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { idx, page in
                        VStack(spacing: 16) {
                            Image(systemName: page.systemImage)
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(ColorTheme.accent)
                                .frame(width: 80, height: 80)
                                .background(RoundedRectangle(cornerRadius: 20).fill(ColorTheme.surface))

                            Text(page.title)
                                .font(.title2.weight(.bold))
                                .foregroundColor(ColorTheme.text)
                                .multilineTextAlignment(.center)

                            Text(page.subtitle)
                                .font(.footnote)
                                .foregroundColor(ColorTheme.subtext)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding(.horizontal, 16)
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack(spacing: 12) {
                    Button("Skip") {
                        onDone()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.subtext)

                    Spacer()

                    Button {
                        if index < pages.count - 1 {
                            withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
                        } else {
                            onDone()
                        }
                    } label: {
                        Text(index < pages.count - 1 ? "Next" : "Get Started")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.accent))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}


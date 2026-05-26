// OnboardingView.swift
// First-time launch flow shown before login.

import SwiftUI

struct OnboardingView: View {
    struct Page: Identifiable {
        let id = UUID()
        let eyebrow: String
        let title: String
        let subtitle: String
        let featureTitle: String
        let featureBody: String
        let accent: Color
        let symbol: String
        let heroTags: [String]
        let buttonLabel: String
        let footerNote: String
    }

    let onDone: () -> Void

    @State private var index: Int = 0

    private let pages: [Page] = [
        Page(
            eyebrow: "YOUR LIBRARY",
            title: "Track the games that matter to you.",
            subtitle: "Log what you played, rate what you loved, and keep a personal history of your taste over time.",
            featureTitle: "Your gaming history, finally in one place",
            featureBody: "Ratings, reviews, saved games, and lists — all connected to the way you actually play.",
            accent: ColorTheme.gold,
            symbol: "gamecontroller.fill",
            heroTags: ["Log Games", "Rate", "Remember"],
            buttonLabel: "Start Your Library",
            footerNote: "Swipe anytime, or keep moving through the welcome flow."
        ),
        Page(
            eyebrow: "YOUR TASTE",
            title: "Your taste deserves a voice.",
            subtitle: "Rate, review, rank, and build lists that actually reflect how you see games — not how someone else scored them.",
            featureTitle: "Say more than “I played it”",
            featureBody: "Write reviews, build rankings, make tier lists, and shape a profile that feels like your own point of view.",
            accent: Color(red: 0.43, green: 0.71, blue: 0.98),
            symbol: "text.quote",
            heroTags: ["Reviews", "Rankings", "Lists"],
            buttonLabel: "Show Your Taste",
            footerNote: "Your profile should feel like your point of view, not just a backlog."
        ),
        Page(
            eyebrow: "TRUSTED DISCOVERY",
            title: "Discover games through real players, not just scores.",
            subtitle: "Follow people who share your taste, find trusted voices, and discover games through community instead of critic consensus or empty algorithms.",
            featureTitle: "Better discovery starts with better people",
            featureBody: "GamerLnd helps you find players whose taste lines up with yours — so recommendations feel personal, earned, and worth trusting.",
            accent: ColorTheme.xpGreen,
            symbol: "person.3.fill",
            heroTags: ["Trusted Gamers", "Shared Taste", "Real Players"],
            buttonLabel: "Find Your People",
            footerNote: "This is the heart of GamerLnd: better discovery through players you trust."
        ),
        Page(
            eyebrow: "GL PROGRESSION",
            title: "Level up as you log, explore, and discover.",
            subtitle: "GL, Milestones, Challenges, and Secrets turn your activity into progression — a fun layer built around the way you already use GamerLnd.",
            featureTitle: "Progress that supports the experience",
            featureBody: "Earn GamerLnd Level, unlock Milestones, complete Challenges, and uncover Secrets as your library and taste keep growing.",
            accent: Color(red: 0.83, green: 0.43, blue: 0.98),
            symbol: "sparkles",
            heroTags: ["GL", "Milestones", "Secrets"],
            buttonLabel: "One More Thing",
            footerNote: "Progression is here to support the experience — not distract from it."
        ),
        Page(
            eyebrow: "BETA FEEDBACK",
            title: "Help us shape GamerLnd the right way.",
            subtitle: "As a beta tester, pay attention to discovery, trust, logging, lists, and anything that feels confusing or broken.",
            featureTitle: "What to test and tell us",
            featureBody: "Flag bugs, rough UX, unclear wording, mismatched ratings, broken links, missing games, and moments where the app does not reflect real player trust.",
            accent: ColorTheme.accent,
            symbol: "bubble.left.and.exclamationmark.bubble.right.fill",
            heroTags: ["Discovery", "Bugs", "Feedback"],
            buttonLabel: "Enter GamerLnd",
            footerNote: "The best beta feedback is specific: what you expected, what happened, and what felt off."
        )
    ]

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(spacing: 0) {
                topBar
                introPager
                footer
            }
        }
        .preferredColorScheme(.dark)
    }

    private var onboardingBackground: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()

            RadialGradient(
                colors: [
                    ColorTheme.gold.opacity(0.22),
                    ColorTheme.background.opacity(0.0)
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 360
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    ColorTheme.xpGreen.opacity(0.12),
                    Color.clear,
                    Color(red: 0.29, green: 0.33, blue: 0.82).opacity(0.14)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 10) {
                Image("icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("GamerLnd")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ColorTheme.text)
                    Text("Beta Welcome")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ColorTheme.subtext)
                }
            }

            Spacer()

            Button("Skip") {
                onDone()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ColorTheme.subtext)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var introPager: some View {
        TabView(selection: $index) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                pageView(page)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 18) {
            heroCard(page)

            VStack(alignment: .leading, spacing: 16) {
                Text(page.eyebrow)
                    .font(.caption.weight(.heavy))
                    .tracking(1.6)
                    .foregroundStyle(page.accent)

                Text(page.title)
                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ColorTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            featureCard(page)

            Spacer(minLength: 0)
        }
    }

    private func heroCard(_ page: Page) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            page.accent.opacity(0.28),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

            VStack(spacing: 18) {
                Image(systemName: page.symbol)
                    .font(.system(size: 50, weight: .black))
                    .foregroundStyle(page.accent)
                    .symbolRenderingMode(.monochrome)

                HStack(spacing: 12) {
                    ForEach(page.heroTags, id: \.self) { tag in
                        onboardingMiniChip(text: tag)
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 220)
    }

    private func featureCard(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(page.accent)
                    .frame(width: 10, height: 10)

                Text(page.featureTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ColorTheme.text)
            }

            Text(page.featureBody)
                .font(.footnote)
                .foregroundStyle(ColorTheme.subtext)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.footerNote)
                .font(.caption)
                .foregroundStyle(ColorTheme.subtext.opacity(0.88))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ColorTheme.surface.opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(ColorTheme.separator, lineWidth: 1)
                )
        )
    }

    private func onboardingMiniChip(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(ColorTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(ColorTheme.surface.opacity(0.82))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }

    private var footer: some View {
        VStack(spacing: 18) {
            pageIndicators

            Button {
                if index < pages.count - 1 {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        index += 1
                    }
                } else {
                    onDone()
                }
            } label: {
                Text(index < pages.count - 1 ? pages[index].buttonLabel : "Continue to Login")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(ColorTheme.gold)
                    )
            }

            Text(index == pages.count - 1 ? "You can start with Apple or email once you continue." : "Swipe anytime, or keep tapping next.")
                .font(.caption)
                .foregroundStyle(ColorTheme.subtext)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .padding(.top, 10)
        .background(
            LinearGradient(
                colors: [
                    Color.clear,
                    ColorTheme.background.opacity(0.84),
                    ColorTheme.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(Array(pages.enumerated()), id: \.offset) { offset, page in
                Capsule(style: .continuous)
                    .fill(offset == index ? page.accent : Color.white.opacity(0.16))
                    .frame(width: offset == index ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.24, dampingFraction: 0.88), value: index)
            }
        }
    }
}
